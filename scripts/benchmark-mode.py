#!/usr/bin/env python3
"""Compare full mode, fast mode and plain Neovim on real input in a PTY.

Every target uses the same Neovim binary, independent copies of the same files,
the same 120x36 grid
and the already-prepared dependencies. Runs alternate target order per sample so
a warming machine cannot favour whichever target happens to go first.

Latency is measured inside Neovim: a key is timestamped when its decoding is
observed, and again at the end of the decoration pass that first reflects it.
That covers the editor's own work, not the terminal's display. The plain-Neovim
target (-u NONE with syntax and line numbers) controls for Neovim's own work;
terminal painting and network latency are outside this measurement.

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
  local info = vim.fn.getwininfo(win)[1]
  local cursor = api.nvim_win_get_cursor(win)
  return {
    top = info.topline, bottom = info.botline, line = cursor[1], col = cursor[2],
    tick = api.nvim_buf_get_changedtick(api.nvim_win_get_buf(win)), mode = api.nvim_get_mode().mode,
  }
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

-- Empty `typed` means a plugin fed the key. Count only terminal input, including
-- the original key of a mapping; animation/completion keys are not new samples.
vim.on_key(function(_, typed)
  if not active then
    return
  end
  if typed and typed ~= "" and active.keys[typed] then
    active.received = active.received + 1
    active.decoded[#active.decoded + 1] = vim.uv.hrtime()
  end
end, namespace)

function _G.BenchStart(phase, keys)
  assert(api.nvim_get_current_win() == win, "Sample window lost focus")
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
  result.mouse = vim.fn.getmousepos()
  result.window = win
  vim.fn.writefile({ vim.json.encode(result) }, run .. "/phase-" .. phase .. ".json")
end

function _G.BenchProgress()
  local last = active.frames[#active.frames]
  return { received = active.received, painted = last and last.received or 0 }
end

function _G.BenchAnchor(index, line)
  api.nvim_set_current_win(win)
  vim.cmd("normal! " .. line .. "Gzt")
  local info = vim.fn.getwininfo(win)[1]
  -- Use the text area's far side, clear of the gutter, scrollbar and
  -- cursor-anchored match-up/diagnostic floats that can appear during a burst.
  -- Fixed terminal coordinates may hit those floats instead of the document.
  local position = api.nvim_win_get_position(win)
  local floats = {}
  for _, other in ipairs(api.nvim_tabpage_list_wins(0)) do
    if other ~= win and api.nvim_win_get_config(other).relative ~= "" then
      local at = api.nvim_win_get_position(other)
      floats[#floats + 1] = { at[1], at[2], at[1] + api.nvim_win_get_height(other) + 1, at[2] + api.nvim_win_get_width(other) + 1 }
    end
  end
  local width, height = api.nvim_win_get_width(win), api.nvim_win_get_height(win)
  local rows = { math.max(1, math.floor(height / 2)) }
  for row = 3, height - 2 do rows[#rows + 1] = row end
  local target
  for column = width - 2, info.textoff + 2, -1 do
    for _, row in ipairs(rows) do
      local x, y = position[2] + column, position[1] + row
      local clear = true
      for _, rect in ipairs(floats) do
        if y >= rect[1] and y <= rect[3] and x >= rect[2] and x <= rect[4] then clear = false; break end
      end
      if clear then target = { column = x, row = y }; break end
    end
    if target then break end
  end
  assert(target, "No unobstructed document cell for wheel measurement")
  vim.fn.writefile({ vim.json.encode(target) }, run .. "/anchor-" .. index .. ".json")
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

    long_lines = ["-- Long-line stress: average width triggers the existing reduced-feature policy."]
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


def disk_usage(directory):
    files = disk_files(directory)
    return {"files": len(files), "bytes": sum((directory / path).stat().st_size for path in files)}


def environment(target, run):
    env = os.environ | {
        "TERM": "xterm-kitty",
        "NVIM_APPNAME": "nvim",
        "NVIM_CHECK_ONLY": "1",
        "NVIM_STATE_DIR": "",
        "XDG_CONFIG_HOME": str(run / "config"),
        "XDG_CACHE_HOME": str(run / "cache"),
        "XDG_STATE_HOME": str(run / "state"),
        "NVIM_LOG_FILE": str(run / "nvim.log"),
        "BENCH_RUN": str(run),
        "SHELL": "/bin/sh",
        # A benchmark must not fetch packages or pollute the user's package
        # cache when a full-mode language server tries automatic type discovery.
        "npm_config_offline": "true",
        "npm_config_cache": str(run / "cache" / "npm"),
        "CARGO_NET_OFFLINE": "true",
    }
    if target != "native":
        env["NVIM_MODE"] = target
    for key in ("KITTY_WINDOW_ID", "WEZTERM_PANE", "TERM_PROGRAM", "NVIM_PARSERS"):
        env.pop(key, None)
    return env


def prepare_run(target, run, data_home):
    (run / "config" / "nvim").mkdir(parents=True, exist_ok=True)
    for entry in ("init.lua", "lua", "after", "spell", "lazy-lock.json"):
        link = run / "config" / "nvim" / entry
        if not link.exists():
            link.symlink_to(ROOT / entry)
    (run / "state").mkdir(parents=True, exist_ok=True)
    (run / "cache").mkdir(parents=True, exist_ok=True)
    if target != "native":
        data = run / "data" / "nvim"
        data.mkdir(parents=True, exist_ok=True)
        for asset in ("lazy", "site", "mason"):
            if (data_home / asset).exists() and not (data / asset).exists():
                (data / asset).symlink_to(data_home / asset, target_is_directory=True)


def copy_sample(sample, run, rust_project=False):
    """All editing and saves use a private file for this target and repetition."""
    workspace = run / "workspace"
    workspace.mkdir(parents=True, exist_ok=True)
    destination = workspace / sample.name
    # Copy bytes, not links or source permissions: even a read-only input can be
    # measured safely, and a formatter can never write back through a symlink.
    with destination.open("xb") as stream:
        stream.write(sample.read_bytes())
    if rust_project:
        # The generated Rust library needs a real, dependency-free crate. A
        # detached file triggers rustaceanvim notices and cannot model Cargo
        # analysis. Real --file inputs remain isolated single-file samples.
        (workspace / "Cargo.toml").write_text(
            '[package]\nname = "nvim_benchmark"\nversion = "0.0.0"\nedition = "2021"\n'
            '[lib]\npath = ' + json.dumps(sample.name) + '\n'
        )
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
        self.startup_prompts = 0
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

    def await_file(self, path, timeout=60, startup=False):
        deadline = time.monotonic() + timeout
        next_prompt_check = time.monotonic() + 0.5
        while not path.exists() and time.monotonic() < deadline:
            self.pump(0.02)
            if startup and self.socket_path.exists() and time.monotonic() >= next_prompt_check:
                self.connect()
                mode = self.request("nvim_get_mode", [], timeout=5)
                # Only acknowledge the hit-enter message, never a confirmation
                # dialog. Rust's standalone-file notice can appear before
                # VimEnter and otherwise prevents the probe from running.
                if mode["mode"] == "r":
                    os.write(self.master, b"\r")
                    self.startup_prompts += 1
                next_prompt_check = time.monotonic() + 0.5
        if not path.exists():
            raise TimeoutError(f"{self.target}: {path} never appeared")
        return path

    def connect(self):
        if self.rpc:
            return
        self.rpc = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.rpc.connect(str(self.socket_path))

    def command(self, text, timeout=60):
        return self.request("nvim_command", [text], timeout)

    def request(self, method, parameters, timeout=60):
        self.identifier += 1
        self.rpc.sendall(msgpack.packb([0, self.identifier, method, parameters], use_bin_type=True))
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
        raise TimeoutError(f"{self.target}: control request timed out: {method}")

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
    The probe excludes plugin-fed keys. Reject missing or extra terminal events
    rather than silently pairing an incomplete input sequence.
    """
    if len(phase["decoded"]) != sent_count:
        raise RuntimeError(f"{phase['phase']}: sent {sent_count} inputs but decoded {len(phase['decoded'])}")
    frames = phase["frames"]
    latencies = []
    for index, decoded in enumerate(phase["decoded"][: max(sent_count, 0)]):
        frame = next((item for item in frames if item["received"] >= index + 1), None)
        if frame is None:
            raise RuntimeError(f"{phase['phase']}: no changed frame for input {index + 1}; inspect phase JSON")
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
    # A pressure sample can still have input queued after one second. Control
    # RPCs may overtake that input; stopping then would report missing keys.
    # Wait for the actual inputs and their frames, bounded so a broken mapping
    # still fails below instead of hanging or yielding a fabricated fast result.
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        progress = session.request("nvim_exec_lua", ["return BenchProgress()", []])
        if progress["received"] >= len(sent) and progress["painted"] >= len(sent):
            break
        session.pump(0.05)
    session.command(f"lua BenchStop({json.dumps(phase)})")
    path = session.await_file(session.run / f"phase-{phase}.json")
    result = json.loads(path.read_text())
    result["sent"] = len(sent)
    result["latencies_ms"] = pair_latencies(result, len(sent))
    return result


def measure_startup(target, sample, run, data_home, repetition=0):
    """Empty startup and first open, taken outside the PTY from Neovim's own log."""
    prepare_run(target, run, data_home)
    env = environment(target, run)
    if target != "native":
        env["XDG_DATA_HOME"] = str(run / "data")
    log = run / f"startup-{repetition}.log"
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
    with (run / f"output-{repetition}.log").open("w") as stream:
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


def run_session(target, sample, run, data_home, options, sample_name=None, rust_project=False):
    measured = copy_sample(sample, run, rust_project=rust_project)
    session = Session(target, measured, run, data_home, options.settle_ms)
    record = {"target": target, "sample": sample.name}
    try:
        ready = json.loads(session.await_file(session.run / "ready.json", timeout=90, startup=True).read_text())
        record["ready"] = ready
        record["startup_prompts_acknowledged"] = session.startup_prompts
        # Includes the fixed settle delay: useful only as a relative figure
        # between targets. Startup itself is measured outside the PTY.
        record["settled_ms"] = round((time.monotonic_ns() - session.started_ns) / 1e6, 1)
        session.connect()
        session.pump(0.2)
        record["idle_rss_kb"] = resident_kb(session.pid)
        record["idle_children"] = child_names(session.pid)
        before = disk_files(run / "state")

        # Send enter-insert + the first character together, timing from `i`.
        # Native Neovim need not redraw the document just to enter insert mode;
        # a real edit gives every target the same visible endpoint and includes
        # InsertEnter setup without adding the inter-character interval.
        first = drive(session, "first_edit", ["i"], [b"ix"], 0)
        record["first_edit_ms"] = round(first["latencies_ms"][0], 3)

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

        session.command(f"lua BenchSave({options.saves})")
        saves = json.loads(session.await_file(session.run / "save.json").read_text())
        record["save"] = summarize(saves)

        # Anchor every scroll inside the document. A burst that reaches the top
        # or the bottom stops changing the viewport, and an event with no redraw
        # cannot be timed at all.
        lines = record["ready"]["lines"]
        top_anchor = 4
        wheel_events = min(20, max(0, (lines - 2 * GRID[1]) // 3))
        bottom_anchor = max(top_anchor + 1, lines - GRID[1])
        wheel = []
        for index in range(options.wheel_bursts if wheel_events else 0):
            down = index % 2 == 0
            session.command(f"lua BenchAnchor({index}, {top_anchor if down else bottom_anchor})")
            session.pump(0.2)
            position = json.loads((run / f"anchor-{index}.json").read_text())
            sequence = f"\x1b[<{65 if down else 64};{position['column']};{position['row']}M".encode()
            phase = drive(session, f"wheel{index}", ["<ScrollWheelUp>", "<ScrollWheelDown>"], [sequence] * wheel_events, 8)
            if phase["mouse"]["winid"] != phase["window"]:
                raise RuntimeError("Wheel input hit a different window; inspect the recorded mouse position")
            wheel += phase["latencies_ms"]
        record["wheel"] = summarize(wheel)
        record["wheel_events"] = wheel_events * options.wheel_bursts
        if not wheel_events or not options.wheel_bursts:
            record["wheel_skipped"] = "document too short" if not wheel_events else "disabled"

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

        if target == "fast" and (sample_name or sample.stem) in options.fast_lsp_sample:
            session.command("lua BenchFastLsp()")
            record["fast_lsp"] = json.loads(session.await_file(session.run / "fastlsp.json", timeout=90).read_text())

        session.pump(0.3)
        session.command("lua BenchReady()")
        record["final"] = json.loads((session.run / "ready.json").read_text())
        record["final_rss_kb"] = resident_kb(session.pid)
        record["new_state_files"] = sorted(disk_files(run / "state") - before)
        record["disk"] = {name: disk_usage(run / name) for name in ("cache", "state", "workspace")}
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
    parser.add_argument(
        "--keep-going", action="store_true",
        help="collect the remaining samples after a failed measurement; exit status stays nonzero",
    )
    options = parser.parse_args()
    if options.runs < 1:
        parser.error("--runs must be at least 1")
    if options.typing_chars < 1 or options.paging_events < 2:
        parser.error("--typing-chars must be positive and --paging-events at least 2")
    if min(options.saves, options.wheel_bursts, options.settle_ms, options.typing_interval_ms, options.paging_interval_ms) < 0:
        parser.error("counts and intervals cannot be negative")
    targets = options.target or list(TARGETS)

    base = options.output or Path(tempfile.mkdtemp(prefix="nvim-mode-benchmark-"))
    if options.output:
        base.mkdir(parents=True, exist_ok=False)
    base = base.resolve()
    data_home = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "nvim"

    samples = build_fixtures(base / "fixtures")
    generated_rust = samples["rust"]
    if options.sample:
        samples = {name: path for name, path in samples.items() if name in options.sample}
        if not samples:
            parser.error("no generated sample matched --sample")
    for extra in options.file:
        path = extra.expanduser().resolve()
        if not path.is_file():
            parser.error(f"not a file: {path}")
        if path.stem in samples:
            parser.error(f"duplicate sample name: {path.stem}")
        samples[path.stem] = path

    unknown = [name for name in options.fast_lsp_sample if name not in samples]
    if unknown:
        parser.error("--fast-lsp-sample does not match any selected sample: " + ", ".join(unknown))

    # Insert-mode bytes: letters and spaces only, so
    # autopairs cannot add characters the measurement did not send.
    letters = "the quick brown fox jumps over the lazy dog "
    typing_bytes = [ord(letters[index % len(letters)]) for index in range(options.typing_chars)]
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
                        # Lua cache keys include the module's path. Reuse the
                        # config path as well as cache; symlinked run-specific
                        # configs would otherwise recompile local modules.
                        run = base / "startup" / cache_mode / scene / target
                        run.mkdir(parents=True, exist_ok=True)
                    else:
                        run.mkdir(parents=True)
                    value = measure_startup(target, sample, run, data_home, run_index)
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
                try:
                    record = run_session(
                        target, sample, run, data_home, options,
                        sample_name=name, rust_project=sample == generated_rust,
                    )
                except (RuntimeError, TimeoutError, OSError) as error:
                    report["failure"] = {"target": target, "sample": name, "run": run_index, "error": str(error)}
                    report.setdefault("failures", []).append(report["failure"])
                    (base / "results.json").write_text(json.dumps(report, indent=2) + "\n")
                    print(f"Measurement failed: {error}. Evidence: {run}", file=sys.stderr)
                    if options.keep_going:
                        continue
                    return 1
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
    return 1 if report.get("failures") else 0


if __name__ == "__main__":
    if shutil.which("nvim") is None:
        raise SystemExit("nvim is required")
    sys.exit(main())
