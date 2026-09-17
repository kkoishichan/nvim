#!/usr/bin/env python3
"""Measure native wheel input to Neovim UI flush using full configuration.

This attaches a real Neovim screen grid through local RPC, bypassing terminal
escape decoding and physical hardware. No plugin callbacks are mocked. Requires
Python msgpack; installs nothing. Use scroll-smoke.py for actual PTY decoding.
"""

import argparse
import collections
import hashlib
import json
import math
import os
import re
import select
import signal
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

try:
    import msgpack
except ImportError:
    raise SystemExit("This optional benchmark requires Python msgpack.") from None


class Editor:
    def __init__(self, root, run, sample, nvim):
        self.run = run
        (self.run / "config").mkdir(parents=True)
        (self.run / "config/nvim").symlink_to(root)
        env = os.environ | {
            "NVIM_APPNAME": "nvim",
            "NVIM_CHECK_ONLY": "1",
            "XDG_CONFIG_HOME": str(self.run / "config"),
            "XDG_CACHE_HOME": str(self.run / "cache"),
            "XDG_STATE_HOME": str(self.run / "state"),
            "NVIM_LOG_FILE": str(self.run / "nvim.log"),
        }
        self.log = (self.run / "stderr.log").open("wb")
        self.process = subprocess.Popen(
            [
                nvim,
                "--embed",
                "--headless",
                "-u",
                str(root / "init.lua"),
                "-i",
                "NONE",
                str(sample),
            ],
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.log,
            start_new_session=True,
        )
        self.unpack = msgpack.Unpacker(raw=False)
        self.pending = collections.deque()
        self.notifications = collections.deque()
        self.identifier = 0
        try:
            self.attach()
        except Exception:
            self.close()
            raise

    def attach(self):
        self.call("nvim_ui_attach", 120, 36, {"ext_linegrid": True})
        self.drain(2)
        self.call(
            "nvim_exec_lua",
            """
          _G.ScrollProbeWin = vim.api.nvim_get_current_win()
          _G.ScrollProbeTop = vim.fn.line('w0')
          vim.api.nvim_create_autocmd('WinScrolled',{callback=function()
            local top = vim.fn.getwininfo(ScrollProbeWin)[1].topline
            if top ~= ScrollProbeTop then
              ScrollProbeTop = top
              vim.rpcnotify(1,'scroll_probe',top)
            end
          end})
        """,
            [],
        )
        self.drain(0.5)

    def next(self, timeout=5):
        if self.pending:
            return self.pending.popleft()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if select.select(
                [self.process.stdout], [], [], max(0, deadline - time.monotonic())
            )[0]:
                data = os.read(self.process.stdout.fileno(), 65536)
                if not data:
                    raise RuntimeError("Neovim closed: " + str(self.run))
                self.unpack.feed(data)
                self.pending.extend(self.unpack)
                if self.pending:
                    return self.pending.popleft()
        raise TimeoutError(str(self.run))

    def call(self, method, *args):
        self.identifier += 1
        ident = self.identifier
        self.process.stdin.write(
            msgpack.packb([0, ident, method, args], use_bin_type=True)
        )
        self.process.stdin.flush()
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            message = self.next(deadline - time.monotonic())
            if message[0] == 1 and message[1] == ident:
                if message[2]:
                    raise RuntimeError(str(message[2]))
                return message[3]
            self.notifications.append(message)
        raise TimeoutError(f"RPC {method} timed out: {self.run}")

    def drain(self, duration):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            try:
                self.next(deadline - time.monotonic())
            except TimeoutError:
                break
        self.notifications.clear()

    def wheel(self, direction="down"):
        self.notifications.clear()
        started = time.perf_counter()
        self.call("nvim_input_mouse", "wheel", direction, "", 0, 10, 40)
        scrolled = False
        while time.perf_counter() - started < 5:
            message = (
                self.notifications.popleft()
                if self.notifications
                else self.next(5 - (time.perf_counter() - started))
            )
            if message[0] != 2:
                continue
            if message[1] == "scroll_probe":
                scrolled = True
            if (
                scrolled
                and message[1] == "redraw"
                and any(x[0] == "flush" for x in message[2])
            ):
                return (time.perf_counter() - started) * 1000
        raise TimeoutError(f"Wheel input did not reach a new frame: {self.run}")

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGTERM)
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait(timeout=5)
        self.process.stdin.close()
        self.process.stdout.close()
        self.log.close()


def metadata(root):
    return {
        "path": str(root),
        "revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True
        ).strip(),
        "working_tree_dirty": bool(
            subprocess.check_output(
                ["git", "status", "--porcelain"], cwd=root, text=True
            ).strip()
        ),
        "lock_sha256": hashlib.sha256(
            (root / "lazy-lock.json").read_bytes()
        ).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--nvim", default="nvim")
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--events", type=int, default=80)
    parser.add_argument(
        "--file",
        type=Path,
        help="read an existing file in its project; scroll down and back up",
    )
    parser.add_argument(
        "--scene",
        action="append",
        choices=("code", "colors", "css_vars"),
        help="repeat to select scenes; defaults to code and colors",
    )
    args = parser.parse_args()
    if args.runs < 1 or args.events < 20 or args.events > 500:
        parser.error("Use at least one run and 20–500 events")
    if args.file and args.scene:
        parser.error("Choose an existing --file or generated --scene fixtures")
    if args.file:
        args.file = args.file.expanduser().resolve()
        if not args.file.is_file():
            parser.error("--file must be an existing file")
    root = (args.root or Path(__file__).resolve().parent.parent).resolve()
    output = args.output or Path(tempfile.mkdtemp(prefix="nvim-scroll-benchmark-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    targets = {"current": root}
    if args.baseline:
        targets = {"baseline": args.baseline.resolve(), "current": root}
    result = {
        "scope": "Full Neovim configuration and screen grid; native wheel input to first UI flush after viewport movement. Includes RPC; excludes terminal escape parsing, compositor and physical device latency.",
        "method": "Alternating target order per run; 8 ms drain between completed events; discard first 10 events per run; nearest-rank p95. This paced test is not a fixed-rate touchpad burst.",
        "nvim": subprocess.check_output(
            [args.nvim, "--version"], text=True
        ).splitlines()[0],
        "targets": {name: metadata(path) for name, path in targets.items()},
        "scenes": {},
    }
    if args.file:
        result["file"] = {
            "path": str(args.file),
            "sha256": hashlib.sha256(args.file.read_bytes()).hexdigest(),
        }
        result["method"] += (
            " Existing files use alternating directions, reversing at viewport boundaries."
            " The source is not edited."
        )
    for scene in args.scene or (("file",) if args.file else ("code", "colors")):
        filetype = "css" if scene == "css_vars" else "lua"
        sample = output / (scene + "." + filetype)
        if scene == "file":
            sample = args.file
            filetype = None
        elif scene == "css_vars":
            sample.write_text(
                ":root { --accent: #44aaff; }\n"
                + "".join(
                    f".item-{index} {{ color: var(--accent); }}\n"
                    for index in range(999)
                )
            )
        else:
            blocks = []
            for index in range(500):
                line = (
                    '  local color = "#44aaff"'
                    if scene == "colors" and index % 10 == 0
                    else "  -- Local calculation"
                )
                blocks.append(
                    "do\n"
                    + line
                    + "\n  local function square(value)\n    return value * value\n  end\nend\n"
                )
            sample.write_text("".join(blocks))
        rows = {name: [] for name in targets}
        for run_index in range(args.runs):
            order = list(targets)
            if run_index % 2:
                order.reverse()
            for name in order:
                editor = Editor(
                    targets[name],
                    output / scene / name / str(run_index + 1),
                    sample,
                    args.nvim,
                )
                try:
                    conditions = editor.call(
                        "nvim_exec_lua",
                        """
                      assert(require('user.core.buffer_policy').allow(0), 'Fixture unexpectedly disabled document features')
                      local expected = ...
                      assert(not expected or vim.bo.filetype == expected, 'Fixture filetype was not recognized')
                      local colors = package.loaded['nvim-highlight-colors']
                      local colors_active = colors and colors.is_active and colors.is_active() or false
                      assert(not expected or colors_active, 'Generated color fixture has no active color plugin')
                      assert(package.loaded.scrollview and vim.g.scrollview_enabled, 'Scrollview is inactive')
                      assert(not package.loaded.neoscroll, 'Wheel unexpectedly loaded Neoscroll')
                      local highlighter = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]
                      return {filetype=vim.bo.filetype, clients=vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({bufnr=0})),
                        treesitter_active=highlighter ~= nil, redraws=highlighter and highlighter.redraw_count or 0,
                        diagnostics=#vim.diagnostic.get(0), colors_active=colors_active,
                        neoscroll_loaded=package.loaded.neoscroll ~= nil}
                    """,
                        [filetype or False],
                    )
                    samples = []
                    directions = []
                    direction = "down"
                    for event_index in range(args.events):
                        if args.file:
                            view = editor.call(
                                "nvim_exec_lua",
                                "return {vim.fn.line('w0'),vim.fn.line('w$'),vim.api.nvim_buf_line_count(0)}",
                                [],
                            )
                            if event_index and event_index % 30 == 0:
                                direction = "up" if direction == "down" else "down"
                            if view[0] <= 1 and view[1] >= view[2]:
                                raise RuntimeError(
                                    "The file fits in the viewport; use a taller file for scrolling measurements"
                                )
                            if view[1] >= view[2]:
                                direction = "up"
                            elif view[0] <= 1:
                                direction = "down"
                        directions.append(direction)
                        samples.append(editor.wheel(direction))
                        editor.drain(0.008)
                    editor.drain(0.2)
                    error = editor.call("nvim_eval", "v:errmsg")
                    if error:
                        raise RuntimeError(error)
                    messages = editor.call("nvim_exec2", "messages", {"output": True})[
                        "output"
                    ]
                    if re.search(
                        r"Failed to run|Error detected while processing|E\d{3,}:",
                        messages,
                    ):
                        raise RuntimeError(messages)
                    marks = editor.call(
                        "nvim_exec_lua",
                        """
                      local ns = vim.api.nvim_get_namespaces()['nvim-highlight-colors']
                      return ns and #vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{}) or 0
                    """,
                        [],
                    )
                    redraws = editor.call(
                        "nvim_exec_lua",
                        "local h=vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]; return h and h.redraw_count or 0",
                        [],
                    )
                    rows[name].append(
                        {
                            "samples_ms": samples,
                            "conditions": conditions,
                            "color_extmarks_after_scroll": marks,
                            "directions": directions,
                            "treesitter_redraws": redraws - conditions["redraws"],
                        }
                    )
                finally:
                    editor.close()
        summaries = {}
        for name, runs in rows.items():
            timings = sorted(value for run in runs for value in run["samples_ms"][10:])
            summaries[name] = {
                "p50_ms": statistics.median(timings),
                "p95_ms": timings[math.ceil(len(timings) * 0.95) - 1],
                "runs": runs,
            }
            print(
                f"{scene} {name}: p50 {summaries[name]['p50_ms']:.2f} ms; p95 {summaries[name]['p95_ms']:.2f} ms",
                flush=True,
            )
        result["scenes"][scene] = summaries
    if args.file and (
        hashlib.sha256(args.file.read_bytes()).hexdigest() != result["file"]["sha256"]
    ):
        raise RuntimeError(
            "The source file changed during measurement; rerun for comparable samples"
        )
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(output / "results.json")


if __name__ == "__main__":
    main()
