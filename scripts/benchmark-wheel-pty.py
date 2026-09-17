#!/usr/bin/env python3
"""Measure paced SGR wheel input through Neovim's core redraw in a PTY.

Uses kitty terminfo; does not launch kitty or measure its GPU/compositor display.
The observer records viewport changes at the end of decoration processing,
before terminal output reaches the display. Requires a POSIX PTY and Neovim.
"""

import argparse
import fcntl
import hashlib
import json
import math
import os
import pty
import re
import select
import signal
import statistics
import struct
import subprocess
import tempfile
import termios
import time
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--file", type=Path, required=True)
parser.add_argument("--baseline", type=Path)
parser.add_argument("--output", type=Path)
parser.add_argument("--runs", type=int, default=4)
parser.add_argument("--bursts", type=int, default=6)
parser.add_argument("--interval-ms", type=float, default=8)
parser.add_argument("--settle-ms", type=int, default=1800)
args = parser.parse_args()
if args.runs < 1 or args.bursts < 2 or args.interval_ms <= 0 or args.settle_ms < 0:
    parser.error(
        "Use positive runs/interval, nonnegative settle time and at least two bursts"
    )
base = args.output or Path(tempfile.mkdtemp(prefix="nvim-wheel-pty-"))
if args.output:
    base.mkdir(parents=True, exist_ok=False)
base = base.resolve()
root = Path(__file__).resolve().parent.parent
source = args.file.expanduser().resolve()
if len(source.read_bytes().splitlines()) < 140:
    parser.error(
        "Use at least 140 lines to keep the wheel bursts away from buffer edges"
    )
digest = hashlib.sha256(source.read_bytes()).hexdigest()
targets = {"baseline": args.baseline.resolve()} if args.baseline else {}
targets["current"] = root


def revision(path):
    return {
        "path": str(path),
        "commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=path, text=True
        ).strip(),
        "dirty": bool(
            subprocess.check_output(
                ["git", "status", "--porcelain"], cwd=path, text=True
            ).strip()
        ),
        "lock_sha256": hashlib.sha256(
            (path / "lazy-lock.json").read_bytes()
        ).hexdigest(),
    }


report = {
    "scope": __doc__,
    "file": str(source),
    "source_sha256": digest,
    "targets": {name: revision(path) for name, path in targets.items()},
    "nvim": subprocess.check_output(["nvim", "--version"], text=True).splitlines()[0],
    "grid": [120, 36],
    "term": "xterm-kitty",
    "events_per_burst": 20,
    "anchor_lines": {"down": 10, "up": 90},
    "observer": "Decoded wheel count paired with viewport changes including virtual rows and wrapped columns",
    "interval_ms": args.interval_ms,
    "settle_ms": args.settle_ms,
    "runs": args.runs,
    "bursts": args.bursts,
}
queries = {
    b"\x1b]11;?": b"\x1b]11;rgb:1f1f/1f1f/1f1f\x1b\\",
    b"\x1b]10;?": b"\x1b]10;rgb:d4d4/d4d4/d4d4\x1b\\",
    b"\x1b[5n": b"\x1b[0n",
    b"\x1b[6n": b"\x1b[1;1R",
    b"\x1b[c": b"\x1b[?1;2c",
    b"\x1b[>c": b"\x1b[>0;0;0c",
    b"\x1bP$qm": b"\x1bP1$r0m\x1b\\",
    b"\x1b[?2026$p": b"\x1b[?2026;2$y",
}
pattern = re.compile(b"|".join(re.escape(k) for k in queries))
rows = []
for run_index in range(args.runs):
    for name in targets if run_index % 2 == 0 else reversed(targets):
        run = base / name / str(run_index)
        run.mkdir(parents=True)
        (run / "config").mkdir()
        (run / "config/nvim").symlink_to(targets[name])
        # Reuse installed read-only assets while keeping language-server
        # workspaces (notably JDTLS) and other generated data in this run.
        installed = (
            Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"
        )
        data = run / "data/nvim"
        data.mkdir(parents=True)
        for asset in ("lazy", "site", "mason"):
            if (installed / asset).exists():
                (data / asset).symlink_to(installed / asset, target_is_directory=True)
        script = run / "probe.lua"
        script.write_text("""
local api=vim.api
local win=api.nvim_get_current_win()
local active
assert(vim.o.mousescroll:match('ver:(%d+)')=='3','Benchmark expects the default three lines per wheel event')
local function view()
 assert(api.nvim_get_current_win()==win,'Benchmark sample lost focus')
 local v=vim.fn.winsaveview()
 return {top=v.topline,fill=v.topfill,skipcol=v.skipcol,leftcol=v.leftcol}
end
local ns=api.nvim_create_namespace('pty_wheel_measurement')
local up,down=vim.keycode('<ScrollWheelUp>'),vim.keycode('<ScrollWheelDown>')
vim.on_key(function(key)
 if active and (key==up or key==down) then active.received=active.received+1 end
end,ns)
api.nvim_set_decoration_provider(ns,{on_end=function()
 if active then
  local now=view()
  if not vim.deep_equal(now,active.last) then
   active.last=now
   active.frames[#active.frames+1]={top=now.top,view=now,received=active.received,ns=vim.uv.hrtime()}
  end
 end
end})
function _G.PtyWheelStart(index)
 local now=view()
 active={start_top=now.top,start_view=now,last=now,received=0,frames={}}
 vim.fn.writefile({'ready'},vim.env.PTY_WHEEL_RUN..'/start-'..index)
end
function _G.PtyWheelStop(index)
 local result=active
 active=nil
 result.end_view=view()
 result.end_top=result.end_view.top
 result.errmsg=vim.v.errmsg
 result.modified=vim.bo.modified
 result.treesitter_active=vim.treesitter.highlighter.active[api.nvim_get_current_buf()]~=nil
 result.neoscroll_loaded=package.loaded.neoscroll~=nil
 result.animation_mapping=vim.fn.maparg('<C-d>','n')~=''
 local cache=package.loaded['user.core.treesitter_predicates']
 local lang=vim.treesitter.language.get_lang(vim.bo.filetype)
 result.query_cache_ready=cache and (cache.is_enabled and cache.is_enabled(lang) or (lang=='python' and cache.setup())) or false
 result.memory_kb=collectgarbage('count')
 result.lsp_clients={}
 for _,client in ipairs(vim.lsp.get_clients({bufnr=api.nvim_get_current_buf()})) do
  result.lsp_clients[#result.lsp_clients+1]={name=client.name,initialized=client.initialized,pending_requests=vim.tbl_count(client.requests or {})}
 end
 vim.fn.writefile({vim.json.encode(result)},vim.env.PTY_WHEEL_RUN..'/result-'..index..'.json')
end
vim.defer_fn(function() vim.fn.writefile({'ready'},vim.env.PTY_WHEEL_RUN..'/ready') end,tonumber(vim.env.PTY_WHEEL_SETTLE_MS))
""")
        env = os.environ | {
            "TERM": "xterm-kitty",
            "NVIM_APPNAME": "nvim",
            "NVIM_CHECK_ONLY": "1",
            "XDG_CONFIG_HOME": str(run / "config"),
            "XDG_DATA_HOME": str(run / "data"),
            "XDG_CACHE_HOME": str(run / "cache"),
            "XDG_STATE_HOME": str(run / "state"),
            "NVIM_LOG_FILE": str(run / "nvim.log"),
            "PTY_WHEEL_RUN": str(run),
            "PTY_WHEEL_SETTLE_MS": str(args.settle_ms),
            "SHELL": "/bin/sh",
        }
        for key in ["KITTY_WINDOW_ID", "WEZTERM_PANE", "TERM_PROGRAM"]:
            env.pop(key, None)
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(root)
            os.execvpe(
                "nvim",
                [
                    "nvim",
                    "-u",
                    str(targets[name] / "init.lua"),
                    "-i",
                    "NONE",
                    "-n",
                    str(source),
                    "--cmd",
                    "autocmd VimEnter * lua dofile(" + json.dumps(str(script)) + ")",
                ],
                env,
            )
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 36, 120, 0, 0))
        log = bytearray()
        buf = b""

        def pump(duration):
            global buf
            deadline = time.monotonic() + duration
            while time.monotonic() < deadline:
                if select.select([master], [], [], max(0, deadline - time.monotonic()))[
                    0
                ]:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        return
                    if not data:
                        return
                    log.extend(data)
                    buf += data
                    end = 0
                    for match in pattern.finditer(buf):
                        os.write(master, queries[match.group()])
                        end = match.end()
                    buf = buf[end:][-20:]

        def await_file(path):
            deadline = time.monotonic() + max(15, args.settle_ms / 1000 + 10)
            while not path.exists() and time.monotonic() < deadline:
                pump(0.02)
            if not path.exists():
                raise TimeoutError(str(path))

        def command(text):
            os.write(master, (":" + text + "\r").encode())

        waves = []
        try:
            await_file(run / "ready")
            pump(0.2)
            for index in range(args.bursts):
                down = index % 2 == 0
                command(f"normal! {10 if down else 90}Gzt")
                pump(0.2)
                command("lua PtyWheelStart(" + str(index) + ")")
                await_file(run / ("start-" + str(index)))
                pump(0.1)
                sequence = f"\x1b[<{65 if down else 64};41;11M".encode()
                sent = []
                start = time.monotonic_ns()
                for event in range(20):
                    deadline = start + int(event * args.interval_ms * 1_000_000)
                    pump(max(0, (deadline - time.monotonic_ns()) / 1e9))
                    sent.append(time.monotonic_ns())
                    os.write(master, sequence)
                pump(0.7)
                command("lua PtyWheelStop(" + str(index) + ")")
                path = run / ("result-" + str(index) + ".json")
                await_file(path)
                wave = json.loads(path.read_text())
                assert not wave["errmsg"] and not wave["modified"], wave
                assert (
                    wave["treesitter_active"]
                    and wave["animation_mapping"]
                    and not wave["neoscroll_loaded"]
                ), wave
                # A wheel step advances screen rows: diagnostics, wrapping,
                # and folds make the logical-line delta variable. Pair each
                # decoded event with the first subsequent viewport redraw.
                assert wave["received"] == len(sent), (name, index, wave)
                assert (wave["end_top"] - wave["start_top"]) * (
                    1 if down else -1
                ) > 0, wave
                completed = [x for x in wave["frames"] if x["received"] == len(sent)]
                assert completed, (
                    "Final event did not change the viewport; check buffer edges or collapsed folds"
                )
                frame = completed[0]
                delays = []
                for event, ns in enumerate(sent):
                    shown = next(
                        x for x in wave["frames"] if x["received"] >= event + 1
                    )
                    delays.append((shown["ns"] - ns) / 1e6)
                wave["sent_ns"] = sent
                wave["latencies_ms"] = delays
                wave["tail_ms"] = (frame["ns"] - sent[-1]) / 1e6
                assert min(delays) >= 0, (name, index, min(delays))
                waves.append(wave)
                pump(0.1)
            values = sorted(x for wave in waves for x in wave["latencies_ms"])
            row = {
                "target": name,
                "run": run_index,
                "waves": waves,
                "p50_ms": statistics.median(values),
                "p95_ms": values[math.ceil(len(values) * 0.95) - 1],
                "median_tail_ms": statistics.median(w["tail_ms"] for w in waves),
            }
            rows.append(row)
            print(
                name,
                run_index,
                "p50",
                round(row["p50_ms"], 2),
                "p95",
                round(row["p95_ms"], 2),
                "tails",
                [round(w["tail_ms"], 1) for w in waves],
                "frames",
                [len(w["frames"]) for w in waves],
                flush=True,
            )
        finally:
            os.killpg(pid, signal.SIGTERM)
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                ended, _ = os.waitpid(pid, os.WNOHANG)
                if ended:
                    break
                time.sleep(0.02)
            else:
                os.killpg(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)
            (run / "terminal.log").write_bytes(log)
assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
report["results"] = rows
(base / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(base / "results.json", flush=True)
