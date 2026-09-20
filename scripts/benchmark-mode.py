#!/usr/bin/env python3
"""Compare full mode, fast mode and plain Neovim on real input in a PTY.

Every target uses the same Neovim binary, the same files, the same 120x36 grid
and the already-prepared dependencies. Runs alternate target order per sample so
a warming machine cannot favour whichever target happens to go first.

Latency is measured inside Neovim: a key is timestamped when its decoding is
observed, and again at the end of the decoration pass that first reflects it.
That covers the editor's own work, not the terminal's display. The plain-Neovim
target (-u NONE with syntax and line numbers) is the control for how much of the
remaining time belongs to file reading, the terminal or the connection.

Alongside latency the report records what a session is running while idle:
attached language clients, active libuv timers, file watchers and child
processes, resident memory including subprocesses, and the files each session
adds to its state directory.
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
import shutil
import signal
import socket
import statistics
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

try:
    import msgpack
except ImportError:
    raise SystemExit("This benchmark requires Python msgpack.") from None

ROOT = Path(__file__).resolve().parent.parent
GRID = (120, 36)
TARGETS = ("full", "fast", "native")

# Terminal replies Neovim asks for at startup. Answering them keeps the session
# from waiting on a real terminal emulator.
QUERIES = {
    b"\x1b]11;?": b"\x1b]11;rgb:1f1f/1f1f/1f1f\x1b\\",
    b"\x1b]10;?": b"\x1b]10;rgb:d4d4/d4d4/d4d4\x1b\\",
    b"\x1b[5n": b"\x1b[0n",
    b"\x1b[6n": b"\x1b[1;1R",
    b"\x1b[c": b"\x1b[?1;2c",
    b"\x1b[>c": b"\x1b[>0;0;0c",
    b"\x1bP$qm": b"\x1bP1$r0m\x1b\\",
    b"\x1b[?2026$p": b"\x1b[?2026;2$y",
}
QUERY_PATTERN = re.compile(b"|".join(re.escape(key) for key in QUERIES))

PROBE = r"""
local api = vim.api
local run = assert(vim.env.BENCH_RUN)
local win = api.nvim_get_current_win()
local original = api.nvim_buf_get_lines(0, 0, -1, false)
local namespace = api.nvim_create_namespace("benchmark_mode")
local active

local function view()
  local v = vim.fn.winsaveview()
  return { top = v.topline, line = v.lnum, col = v.col, fill = v.topfill, leftcol = v.leftcol }
end

local function handles()
  local counts = { timer = 0, fs_event = 0, fs_poll = 0, process = 0, idle = 0 }
  vim.uv.walk(function(handle)
    local kind = handle:get_type()
    if counts[kind] ~= nil and handle:is_active() and not handle:is_closing() then
      counts[kind] = counts[kind] + 1
    end
  end)
  return counts
end

local function state()
  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients()) do
    clients[#clients + 1] = { name = client.name, initialized = client.initialized }
  end
  local diagnostics = 0
  for _, _ in ipairs(vim.diagnostic.get(api.nvim_get_current_buf())) do
    diagnostics = diagnostics + 1
  end
  return {
    clients = clients,
    diagnostics = diagnostics,
    handles = handles(),
    lua_kb = collectgarbage("count"),
    treesitter = vim.treesitter.highlighter.active[api.nvim_get_current_buf()] ~= nil,
    filetype = vim.bo.filetype,
    lines = api.nvim_buf_line_count(0),
  }
end

api.nvim_set_decoration_provider(namespace, {
  on_end = function()
    if not active then
      return
    end
    local now = view()
    if not vim.deep_equal(now, active.last) then
      active.last = now
      active.frames[#active.frames + 1] = { received = active.received, ns = vim.uv.hrtime() }
    end
  end,
})

-- `typed` is what the terminal delivered; `key` is what it became after
-- mapping. A mode that animates <C-d> must still be measured against the key
-- the user pressed, so prefer `typed` and fall back for unmapped input.
vim.on_key(function(key, typed)
  if not active then
    return
  end
  local observed = (typed ~= nil and typed ~= "") and typed or key
  if active.keys[observed] then
    active.received = active.received + 1
    active.decoded[#active.decoded + 1] = vim.uv.hrtime()
  end
end, namespace)

function _G.BenchStart(phase, keys)
  local wanted = {}
  for _, key in ipairs(keys) do
    wanted[vim.keycode(key)] = true
  end
  active = { phase = phase, keys = wanted, received = 0, decoded = {}, frames = {}, last = view() }
  vim.fn.writefile({ "ready" }, run .. "/start-" .. phase)
end

function _G.BenchStop(phase)
  local result = active
  active = nil
  -- The watched keys are Neovim's internal encodings, which are not text.
  -- Keep them out of the result rather than writing invalid UTF-8.
  result.keys = nil
  result.errmsg = vim.v.errmsg
  result.state = state()
  vim.fn.writefile({ vim.json.encode(result) }, run .. "/phase-" .. phase .. ".json")
end

-- Saving is a command, not a key: time it where it happens instead of guessing
-- from a redraw.
function _G.BenchRestore()
  api.nvim_buf_set_lines(0, 0, -1, false, original)
end

function _G.BenchSave(count)
  local samples = {}
  for index = 1, count do
    -- Each save starts with the same valid source, even if a formatter changed
    -- the previous copy. No language-specific comment is injected.
    BenchRestore()
    vim.bo.modified = true
    local began = vim.uv.hrtime()
    vim.cmd("silent write")
    samples[#samples + 1] = (vim.uv.hrtime() - began) / 1e6
  end
  BenchRestore()
  vim.fn.writefile({ vim.json.encode(samples) }, run .. "/save.json")
end

-- The first on-demand language server is a separate cost from ordinary editing,
-- so it is measured and reported on its own.
function _G.BenchFastLsp()
  local loaded, fast = pcall(require, "user.core.fast_lsp")
  local candidates = loaded and fast.candidates(0) or {}
  if #candidates == 0 then
    local report = { ok = false, reason = "no installed server for this filetype", state = state() }
    vim.fn.writefile({ vim.json.encode(report) }, run .. "/fastlsp.json")
    return
  end
  -- Name the server instead of opening the chooser: this measures the cost of
  -- the first on-demand start, not of answering a prompt.
  local server = candidates[1]
  local began = vim.uv.hrtime()
  local ok = pcall(vim.cmd, "FastLspStart " .. server)
  local attached = ok
    and vim.wait(30000, function()
      return #vim.lsp.get_clients({ bufnr = 0 }) > 0
    end, 25)
  local elapsed = (vim.uv.hrtime() - began) / 1e6
  local settled = vim.wait(20000, function()
    return #vim.diagnostic.get(vim.api.nvim_get_current_buf()) > 0
  end, 50)
  local report = {
    ok = ok and attached or false,
    server = server,
    ms = elapsed,
    diagnostics_ms = (vim.uv.hrtime() - began) / 1e6,
    diagnostics_arrived = settled,
    state = state(),
  }
  vim.fn.writefile({ vim.json.encode(report) }, run .. "/fastlsp.json")
end

function _G.BenchReady()
  vim.fn.writefile({ vim.json.encode(state()) }, run .. "/ready.json")
end

vim.defer_fn(function()
  vim.cmd("normal! gg")
  _G.BenchReady()
end, tonumber(vim.env.BENCH_SETTLE_MS))
"""


def revision():
    return {
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
        "lock_sha256": hashlib.sha256((ROOT / "lazy-lock.json").read_bytes()).hexdigest(),
    }


def build_fixtures(directory):
    """Deterministic samples covering the languages and shapes under test."""
    directory.mkdir(parents=True, exist_ok=True)
    files = {}

    lua = ["-- Sample module for latency measurement.", "local M = {}", ""]
    for index in range(1, 61):
        lua += [
            f"function M.step_{index}(value)",
            "\tlocal total = 0",
            f"\tfor i = 1, {index} do",
            "\t\ttotal = total + (value or 0) * i",
            "\tend",
            "\treturn total",
            "end",
            "",
        ]
    lua.append("return M")
    files["lua"] = ("sample.lua", "\n".join(lua) + "\n")

    ts = ["export interface Point {", "  x: number;", "  y: number;", "}", ""]
    for index in range(1, 51):
        ts += [
            f"export function scale{index}(point: Point, factor: number): Point {{",
            f"  const shift = {index};",
            "  return { x: point.x * factor + shift, y: point.y * factor - shift };",
            "}",
            "",
        ]
    files["typescript"] = ("sample.ts", "\n".join(ts) + "\n")

    js = ["'use strict';", ""]
    for index in range(1, 51):
        js += [
            f"function accumulate{index}(items) {{",
            "  return items.reduce((total, item) => total + item, 0);",
            "}",
            "",
        ]
    js.append("module.exports = { accumulate1 };")
    files["javascript"] = ("sample.js", "\n".join(js) + "\n")

    rust = ["#![allow(dead_code)]", "", "pub struct Matrix {", "    rows: usize,", "    data: Vec<f64>,", "}", ""]
    for index in range(1, 41):
        rust += [
            f"pub fn combine_{index}(left: &[f64], right: &[f64]) -> Vec<f64> {{",
            "    left.iter().zip(right.iter()).map(|(a, b)| a * b).collect()",
            "}",
            "",
        ]
    files["rust"] = ("sample.rs", "\n".join(rust) + "\n")

    c = ["#include <stdio.h>", "#include <stdlib.h>", ""]
    for index in range(1, 41):
        c += [
            f"static int reduce_{index}(const int *values, int count) {{",
            "    int total = 0;",
            "    for (int i = 0; i < count; ++i) {",
            "        total += values[i];",
            "    }",
            "    return total;",
            "}",
            "",
        ]
    c.append("int main(void) { return 0; }")
    files["c"] = ("sample.c", "\n".join(c) + "\n")

    cpp = ["#include <vector>", "#include <string>", "", "namespace sample {", ""]
    for index in range(1, 41):
        cpp += [
            f"std::vector<int> expand_{index}(const std::vector<int> &input) {{",
            "    std::vector<int> output;",
            "    output.reserve(input.size());",
            "    for (const auto &value : input) {",
            "        output.push_back(value * 2);",
            "    }",
            "    return output;",
            "}",
            "",
        ]
    cpp.append("}  // namespace sample")
    files["cpp"] = ("sample.cpp", "\n".join(cpp) + "\n")

    sql = ["-- Reporting queries.", ""]
    for index in range(1, 41):
        sql += [
            f"CREATE OR REPLACE VIEW report_{index} AS",
            "SELECT account_id, sum(amount) AS total, count(*) AS entries",
            "FROM ledger",
            f"WHERE posted_at >= now() - interval '{index} days'",
            "GROUP BY account_id;",
            "",
        ]
    files["sql"] = ("sample.sql", "\n".join(sql) + "\n")

    markdown = ["# Sample document", ""]
    for index in range(1, 41):
        markdown += [
            f"## Section {index}",
            "",
            "Prose paragraph with `inline code`, a [link](https://example.invalid) and *emphasis*.",
            "",
            "```lua",
            f"local value = {index}",
            "```",
            "",
        ]
    files["markdown"] = ("sample.md", "\n".join(markdown) + "\n")

    long_lines = ["-- Long lines stay under the reduced-feature ceiling on purpose."]
    for index in range(1, 181):
        long_lines.append(f"local row_{index} = {{ " + ", ".join(f'"{n:04d}"' for n in range(90)) + " }")
    files["long_lines"] = ("long-lines.lua", "\n".join(long_lines) + "\n")

    big = ["-- Large document that crosses the reduced-feature line ceiling."]
    for index in range(1, 12001):
        big.append(f"local entry_{index} = {{ id = {index}, name = 'item {index}' }}")
    files["big_file"] = ("big.lua", "\n".join(big) + "\n")

    # Deliberate errors, so a session with a language server has real work.
    noisy = ["import os", "import sys", ""]
    for index in range(1, 41):
        noisy += [
            f"def broken_{index}(value: int) -> str:",
            f"    missing_name_{index}",
            "    return value",
            "",
        ]
    files["diagnostics"] = ("diagnostics.py", "\n".join(noisy) + "\n")

    written = {}
    for key, (name, content) in files.items():
        path = directory / name
        path.write_text(content)
        written[key] = path
    return written


def descendants(pid):
    found, queue = [], [pid]
    while queue:
        current = queue.pop()
        try:
            children = Path(f"/proc/{current}/task").iterdir()
        except OSError:
            continue
        for task in children:
            try:
                kids = (task / "children").read_text().split()
            except OSError:
                continue
            for kid in kids:
                found.append(int(kid))
                queue.append(int(kid))
    return found


def child_names(pid):
    names = []
    for target in descendants(pid):
        try:
            names.append(Path(f"/proc/{target}/comm").read_text().strip())
        except OSError:
            names.append("unknown")
    return sorted(names)


def resident_kb(pid):
    total = 0
    for target in [pid] + descendants(pid):
        try:
            status = Path(f"/proc/{target}/status").read_text()
        except OSError:
            continue
        match = re.search(r"^VmRSS:\s+(\d+) kB", status, re.MULTILINE)
        if match:
            total += int(match.group(1))
    return total


def disk_files(directory):
    if not directory.exists():
        return set()
    return {str(path.relative_to(directory)) for path in directory.rglob("*") if path.is_file()}


def environment(target, run):
    env = os.environ | {
        "TERM": "xterm-kitty",
        "NVIM_APPNAME": "nvim",
        "NVIM_CHECK_ONLY": "1",
        "XDG_CONFIG_HOME": str(run / "config"),
        "XDG_CACHE_HOME": str(run / "cache"),
        "XDG_STATE_HOME": str(run / "state"),
        "NVIM_LOG_FILE": str(run / "nvim.log"),
        "BENCH_RUN": str(run),
        "SHELL": "/bin/sh",
    }
    if target != "native":
        env["NVIM_MODE"] = target
    for key in ("KITTY_WINDOW_ID", "WEZTERM_PANE", "TERM_PROGRAM", "NVIM_PARSERS"):
        env.pop(key, None)
    return env


def prepare_run(target, run, data_home):
    (run / "config" / "nvim").mkdir(parents=True)
    for entry in ("init.lua", "lua", "after", "spell", "lazy-lock.json"):
        (run / "config" / "nvim" / entry).symlink_to(ROOT / entry)
    (run / "state").mkdir(parents=True, exist_ok=True)
    (run / "cache").mkdir(parents=True, exist_ok=True)
    if target != "native":
        data = run / "data" / "nvim"
        data.mkdir(parents=True)
        for asset in ("lazy", "site", "mason"):
            if (data_home / asset).exists():
                (data / asset).symlink_to(data_home / asset, target_is_directory=True)


def copy_sample(sample, run):
    """All editing and saves use a private file for this target and repetition."""
    workspace = run / "workspace"
    workspace.mkdir(parents=True, exist_ok=True)
    destination = workspace / sample.name
    # Copy bytes, not links or source permissions: even a read-only input can be
    # measured safely, and a formatter can never write back through a symlink.
    with destination.open("xb") as stream:
        stream.write(sample.read_bytes())
    return destination


def launch_argv(target, sample, probe):
    if target == "native":
        # The control: no configuration at all, with the display settings the
        # measurement needs so the comparison is about work, not about layout.
        return [
            "nvim",
            "-u",
            "NONE",
            "-i",
            "NONE",
            "-n",
            "--cmd",
            "syntax on | set number relativenumber laststatus=3 scrolloff=8 termguicolors",
            "--cmd",
            "autocmd VimEnter * lua dofile(" + json.dumps(str(probe)) + ")",
            str(sample),
        ]
    return [
        "nvim",
        "-u",
        str(ROOT / "init.lua"),
        "-i",
        "NONE",
        "-n",
        "--cmd",
        "autocmd VimEnter * lua dofile(" + json.dumps(str(probe)) + ")",
        str(sample),
    ]


class Session:
    """One measured Neovim process behind a PTY, controlled over local RPC."""

    def __init__(self, target, sample, run, data_home, settle_ms):
        self.run = run
        self.target = target
        self.log = bytearray()
        self.buffer = b""
        self.identifier = 0
        self.unpacker = msgpack.Unpacker(raw=False)
        self.rpc = None
        prepare_run(target, run, data_home)
        probe = run / "probe.lua"
        probe.write_text(PROBE)
        env = environment(target, run)
        env["BENCH_SETTLE_MS"] = str(settle_ms)
        if target != "native":
            env["XDG_DATA_HOME"] = str(run / "data")
        self.socket_dir = tempfile.TemporaryDirectory(prefix="nvim-mode-rpc-")
        self.socket_path = Path(self.socket_dir.name) / "socket"
        argv = launch_argv(target, sample, probe)
        argv = argv[:1] + ["--listen", str(self.socket_path)] + argv[1:]
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            os.chdir(ROOT)
            os.execvpe("nvim", argv, env)
        fcntl_winsize(self.master, GRID)
        self.started_ns = time.monotonic_ns()

    def pump(self, duration):
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            if select.select([self.master], [], [], max(0, deadline - time.monotonic()))[0]:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    return
                if not data:
                    return
                self.log.extend(data)
                self.buffer += data
                end = 0
                for match in QUERY_PATTERN.finditer(self.buffer):
                    os.write(self.master, QUERIES[match.group()])
                    end = match.end()
                self.buffer = self.buffer[end:][-20:]

    def await_file(self, path, timeout=60):
        deadline = time.monotonic() + timeout
        while not path.exists() and time.monotonic() < deadline:
            self.pump(0.02)
        if not path.exists():
            raise TimeoutError(f"{self.target}: {path} never appeared")
        return path

    def connect(self):
        self.rpc = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.rpc.connect(str(self.socket_path))

    def command(self, text, timeout=60):
        self.identifier += 1
        self.rpc.sendall(msgpack.packb([0, self.identifier, "nvim_command", [text]], use_bin_type=True))
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if select.select([self.rpc], [], [], 0)[0]:
                data = self.rpc.recv(65536)
                if not data:
                    raise RuntimeError("Neovim closed the control channel")
                self.unpacker.feed(data)
                for message in self.unpacker:
                    if message[0] == 1 and message[1] == self.identifier:
                        if message[2]:
                            raise RuntimeError(f"{self.target}: {message[2]}")
                        return message[3]
            self.pump(0.005)
        raise TimeoutError(f"{self.target}: control request timed out: {text}")

    def close(self):
        if self.rpc:
            self.rpc.close()
        try:
            os.killpg(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            ended, _ = os.waitpid(self.pid, os.WNOHANG)
            if ended:
                break
            time.sleep(0.02)
        else:
            os.killpg(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        os.close(self.master)
        self.socket_dir.cleanup()
        (self.run / "terminal.log").write_bytes(self.log)


def fcntl_winsize(master, grid):
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", grid[1], grid[0], 0, 0))


def summarize(values):
    if not values:
        return None
    ordered = sorted(values)
    return {
        "samples": len(ordered),
        "p50_ms": round(statistics.median(ordered), 3),
        "p95_ms": round(ordered[math.ceil(len(ordered) * 0.95) - 1], 3),
        "max_ms": round(ordered[-1], 3),
        "over_50ms": sum(1 for value in ordered if value > 50),
        "over_100ms": sum(1 for value in ordered if value > 100),
    }


def pair_latencies(phase, sent_count):
    """Pair each decoded key with the first decoration pass that reflected it.

    Both timestamps are taken inside Neovim, so the value is the editor's own
    work and cannot go negative: the frame is recorded after the key it counts.
    Plugins that feed keys of their own show up as extra samples, which is why
    the decoded count is reported next to the number of keys actually sent.
    """
    frames = phase["frames"]
    latencies = []
    for index, decoded in enumerate(phase["decoded"][: max(sent_count, 0)]):
        frame = next((item for item in frames if item["received"] >= index + 1), None)
        if frame is None:
            continue
        latencies.append((frame["ns"] - decoded) / 1e6)
    return latencies


def drive(session, phase, keys, sequences, interval_ms):
    # A Lua list literal, not JSON: the probe is called through :lua.
    literal = "{" + ",".join(json.dumps(key) for key in keys) + "}"
    session.command(f"lua BenchStart({json.dumps(phase)}, {literal})")
    session.await_file(session.run / ("start-" + phase))
    session.pump(0.15)
    sent = []
    start = time.monotonic_ns()
    for index, sequence in enumerate(sequences):
        deadline = start + int(index * interval_ms * 1_000_000)
        session.pump(max(0, (deadline - time.monotonic_ns()) / 1e9))
        sent.append(time.monotonic_ns())
        os.write(session.master, sequence)
    session.pump(1.0)
    session.command(f"lua BenchStop({json.dumps(phase)})")
    path = session.await_file(session.run / f"phase-{phase}.json")
    result = json.loads(path.read_text())
    result["sent"] = len(sent)
    result["latencies_ms"] = pair_latencies(result, len(sent))
    return result


def measure_startup(target, sample, run, data_home):
    """Empty startup and first open, taken outside the PTY from Neovim's own log."""
    prepare_run(target, run, data_home)
    env = environment(target, run)
    if target != "native":
        env["XDG_DATA_HOME"] = str(run / "data")
    log = run / "startup.log"
    argv = ["nvim", "--headless"]
    if target == "native":
        argv += ["-u", "NONE"]
    else:
        argv += ["-u", str(ROOT / "init.lua")]
    argv += [
        "-i",
        "NONE",
        "--startuptime",
        str(log),
        "--cmd",
        "autocmd VimEnter * lua vim.defer_fn(function() vim.cmd('qa!') end, 150)",
    ]
    if sample:
        argv.append(str(sample))
    with (run / "output.log").open("w") as stream:
        process = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=stream, stderr=stream, start_new_session=True)
        try:
            code = process.wait(timeout=60)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
            raise RuntimeError(f"Startup timed out: {run}") from None
    if code != 0:
        raise RuntimeError(f"Startup exited {code}: {run / 'output.log'}")
    match = re.search(r"^\s*([\d.]+).*NVIM STARTED", log.read_text(), re.MULTILINE)
    if not match:
        raise RuntimeError(f"Startup milestone missing: {log}")
    return float(match.group(1))


def run_session(target, sample, run, data_home, options):
    measured = copy_sample(sample, run)
    session = Session(target, measured, run, data_home, options.settle_ms)
    record = {"target": target, "sample": sample.name}
    try:
        ready = json.loads(session.await_file(session.run / "ready.json", timeout=90).read_text())
        record["ready"] = ready
        # Includes the fixed settle delay: useful only as a relative figure
        # between targets. Startup itself is measured outside the PTY.
        record["settled_ms"] = round((time.monotonic_ns() - session.started_ns) / 1e6, 1)
        session.connect()
        session.pump(0.2)
        record["idle_rss_kb"] = resident_kb(session.pid)
        record["idle_children"] = child_names(session.pid)
        before = disk_files(run / "state")

        typing = drive(
            session,
            "typing",
            [chr(code) for code in range(ord("a"), ord("z") + 1)] + ["<Space>"],
            [bytes([code]) for code in options.typing_bytes],
            options.typing_interval_ms,
        )
        # Typing ran in insert mode; leave it, or the paging keys would be
        # insert-mode editing commands instead of half-page scrolls.
        session.command("stopinsert")
        session.command("lua BenchRestore()")
        record["typing"] = summarize(typing["latencies_ms"])
        record["typing_keys"] = {"sent": typing["sent"], "decoded": len(typing["decoded"])}
        record["first_key_ms"] = round(typing["latencies_ms"][0], 3) if typing["latencies_ms"] else None

        session.command(f"lua BenchSave({options.saves})")
        saves = json.loads(session.await_file(session.run / "save.json").read_text())
        record["save"] = summarize(saves)

        # Anchor every scroll inside the document. A burst that reaches the top
        # or the bottom stops changing the viewport, and an event with no redraw
        # cannot be timed at all.
        lines = record["ready"]["lines"]
        wheel_span = 20 * 3 + GRID[1]
        top_anchor = 4
        bottom_anchor = max(top_anchor + 1, lines - wheel_span - GRID[1])
        wheel = []
        for index in range(options.wheel_bursts):
            down = index % 2 == 0
            session.command(f"normal! {top_anchor if down else bottom_anchor}Gzt")
            session.pump(0.2)
            sequence = f"\x1b[<{65 if down else 64};41;11M".encode()
            phase = drive(session, f"wheel{index}", ["<ScrollWheelUp>", "<ScrollWheelDown>"], [sequence] * 20, 8)
            wheel += phase["latencies_ms"]
        record["wheel"] = summarize(wheel)

        # Half a page per key, so the run goes down and then back to where it
        # started without ever hitting an edge.
        half = max(1, min(options.paging_events // 2, max(1, (lines - 2 * GRID[1] - 20) // GRID[1])))
        session.command(f"normal! {top_anchor}Gzt")
        session.pump(0.2)
        paging = drive(
            session,
            "paging",
            ["<C-d>", "<C-u>"],
            [b"\x04"] * half + [b"\x15"] * half,
            options.paging_interval_ms,
        )
        record["paging"] = summarize(paging["latencies_ms"])
        record["paging_events"] = 2 * half

        if target == "fast" and sample.stem in options.fast_lsp_sample:
            session.command("lua BenchFastLsp()")
            record["fast_lsp"] = json.loads(session.await_file(session.run / "fastlsp.json", timeout=90).read_text())

        session.pump(0.3)
        session.command("lua BenchReady()")
        record["final"] = json.loads((session.run / "ready.json").read_text())
        record["final_rss_kb"] = resident_kb(session.pid)
        record["new_state_files"] = sorted(disk_files(run / "state") - before)
    finally:
        session.close()
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, help="new output directory")
    parser.add_argument("--runs", type=int, default=3, help="interleaved runs per target and sample")
    parser.add_argument("--target", choices=TARGETS, action="append", help="repeatable; default: all three")
    parser.add_argument("--file", type=Path, action="append", default=[], help="extra real file to measure; repeatable")
    parser.add_argument("--sample", action="append", help="limit generated samples by name")
    parser.add_argument("--settle-ms", type=int, default=2000)
    parser.add_argument("--typing-chars", type=int, default=40)
    parser.add_argument("--typing-interval-ms", type=float, default=25)
    parser.add_argument("--saves", type=int, default=5)
    parser.add_argument("--wheel-bursts", type=int, default=4)
    parser.add_argument("--paging-events", type=int, default=12)
    parser.add_argument("--paging-interval-ms", type=float, default=80)
    parser.add_argument(
        "--fast-lsp-sample",
        action="append",
        default=[],
        metavar="NAME",
        help="also measure the first :FastLspStart in fast mode for this sample; repeatable",
    )
    parser.add_argument("--startup-cache", choices=("cold", "warm", "both"), default="both")
    options = parser.parse_args()
    if options.runs < 1:
        parser.error("--runs must be at least 1")
    targets = options.target or list(TARGETS)

    base = options.output or Path(tempfile.mkdtemp(prefix="nvim-mode-benchmark-"))
    if options.output:
        base.mkdir(parents=True, exist_ok=False)
    base = base.resolve()
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"

    samples = build_fixtures(base / "fixtures")
    if options.sample:
        samples = {name: path for name, path in samples.items() if name in options.sample}
        if not samples:
            parser.error("no generated sample matched --sample")
    for extra in options.file:
        path = extra.expanduser().resolve()
        if not path.is_file():
            parser.error(f"not a file: {path}")
        samples[path.stem] = path

    unknown = [name for name in options.fast_lsp_sample if name not in {path.stem for path in samples.values()}]
    if unknown:
        parser.error("--fast-lsp-sample does not match any selected sample: " + ", ".join(unknown))

    # Insert-mode bytes: a leading `i`, then letters and spaces only, so
    # autopairs cannot add characters the measurement did not send.
    letters = "the quick brown fox jumps over the lazy dog "
    typing_bytes = [ord("i")] + [ord(letters[index % len(letters)]) for index in range(options.typing_chars)]
    options.typing_bytes = typing_bytes

    report = {
        "scope": __doc__,
        "benchmark_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "nvim": subprocess.check_output(["nvim", "--version"], text=True).splitlines()[0],
        "configuration": revision(),
        "grid": list(GRID),
        "term": "xterm-kitty",
        "targets": targets,
        "runs": options.runs,
        "typing": {"chars": options.typing_chars, "interval_ms": options.typing_interval_ms},
        "wheel": {"bursts": options.wheel_bursts, "events_per_burst": 20, "interval_ms": 8},
        "paging": {"events": options.paging_events, "interval_ms": options.paging_interval_ms},
        "fast_lsp_samples": options.fast_lsp_sample,
        "samples": {
            name: {
                "path": str(path),
                "bytes": path.stat().st_size,
                "lines": len(path.read_bytes().splitlines()),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
            for name, path in samples.items()
        },
        "startup": [],
        "sessions": [],
    }

    # Startup: empty and first open, cold and warm compilation cache.
    modes = ("cold", "warm") if options.startup_cache == "both" else (options.startup_cache,)
    for cache_mode in modes:
        for scene, sample in [("empty", None), ("first_open", samples.get("lua"))]:
            if scene == "first_open" and sample is None:
                continue
            for run_index in range(options.runs + 1):
                order = targets if run_index % 2 == 0 else list(reversed(targets))
                for target in order:
                    run = base / "startup" / cache_mode / scene / target / str(run_index)
                    if cache_mode == "warm":
                        shared = base / "startup" / "warm-cache" / target
                        shared.mkdir(parents=True, exist_ok=True)
                        run.mkdir(parents=True)
                        (run / "cache").symlink_to(shared, target_is_directory=True)
                    else:
                        run.mkdir(parents=True)
                    value = measure_startup(target, sample, run, data_home)
                    if run_index == 0:
                        continue  # discard the first sample of each series
                    report["startup"].append(
                        {"cache": cache_mode, "scene": scene, "target": target, "run": run_index, "ms": value}
                    )
                    print(f"startup {cache_mode} {scene} {target} #{run_index}: {value:.2f} ms", flush=True)

    for name, sample in samples.items():
        for run_index in range(options.runs):
            order = targets if run_index % 2 == 0 else list(reversed(targets))
            for target in order:
                run = base / "session" / name / target / str(run_index)
                run.mkdir(parents=True)
                record = run_session(target, sample, run, data_home, options)
                record["run"] = run_index
                report["sessions"].append(record)
                typing = record.get("typing") or {}
                print(
                    f"{name} {target} #{run_index}: settled {record['settled_ms']:.0f} ms, "
                    f"typing p50 {typing.get('p50_ms')} p95 {typing.get('p95_ms')}, "
                    f"clients {len(record['final']['clients'])}, "
                    f"timers {record['final']['handles']['timer']}, "
                    f"watchers {record['final']['handles']['fs_event']}, "
                    f"children {record['idle_children']}, rss {record['final_rss_kb']} kB",
                    flush=True,
                )

    (base / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(base / "results.json", flush=True)
    return 0


if __name__ == "__main__":
    if shutil.which("nvim") is None:
        raise SystemExit("nvim is required")
    sys.exit(main())
