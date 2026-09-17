#!/usr/bin/env python3
"""Check real terminal SGR wheel decoding and viewport behavior in an isolated PTY."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import tempfile
import termios
import time


SNAPSHOT = r'''
function _G.NvimScrollSnapshot(name, attempt)
  local windows = {}
  local bars = {}
  local tab_windows = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(tab_windows) do
    local ok, props = pcall(vim.api.nvim_win_get_var, win, "scrollview_props")
    if ok and props.type == 0 and props.parent_winid then
      bars[props.parent_winid] = {
        id = win, row = props.row, height = props.height,
        count = (bars[props.parent_winid] or {}).count or 0,
      }
      bars[props.parent_winid].count = bars[props.parent_winid].count + 1
    end
  end
  local namespace = vim.api.nvim_get_namespaces()["nvim-highlight-colors"]
  for _, win in ipairs(tab_windows) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      local buf = vim.api.nvim_win_get_buf(win)
      local info = vim.fn.getwininfo(win)[1]
      local rows = {}
      if namespace then
        local marks = vim.api.nvim_buf_get_extmarks(buf, namespace,
          {info.topline - 1, 0}, {info.botline, 0}, {details = true})
        for _, mark in ipairs(marks) do
          local hl = mark[4].hl_group
          if hl and mark[2] + 1 >= info.topline and mark[2] + 1 <= info.botline then
            local color = vim.api.nvim_get_hl(0, {name = hl, link = false})
            if color.bg == 0xabcdef then rows[tostring(mark[2] + 1)] = true end
          end
        end
      end
      windows[#windows + 1] = {
        id = win, buffer = buf, name = vim.api.nvim_buf_get_name(buf),
        row = info.winrow, column = info.wincol,
        width = info.width, height = info.height,
        topline = info.topline, botline = info.botline,
        cursor = vim.api.nvim_win_get_cursor(win), color_rows = vim.tbl_keys(rows),
        scrollbar = bars[win],
      }
    end
  end
  -- VimEnter does not guarantee that the first deferred scrollbar draw has
  -- completed. Wait for its actual readiness, with a bounded retry budget.
  if name == "ready" and (attempt or 0) < 60 then
    for _, win in ipairs(windows) do
      if not win.scrollbar then
        vim.defer_fn(function() NvimScrollSnapshot(name, (attempt or 0) + 1) end, 50)
        return
      end
    end
  end
  vim.fn.writefile({vim.json.encode({
    windows = windows, current = vim.api.nvim_get_current_win(),
    mode = vim.api.nvim_get_mode().mode, errmsg = vim.v.errmsg,
    messages = vim.api.nvim_exec2("messages", {output = true}).output,
    neoscroll_loaded = package.loaded.neoscroll ~= nil,
    colors_loaded = package.loaded["nvim-highlight-colors"] ~= nil,
    options = {mouse = vim.o.mouse, mousescroll = vim.o.mousescroll,
      ttimeout = vim.o.ttimeout, ttimeoutlen = vim.o.ttimeoutlen,
      timeoutlen = vim.o.timeoutlen, smoothscroll = vim.wo.smoothscroll},
    wheel_mappings = {down = vim.fn.maparg("<ScrollWheelDown>", "n"),
      up = vim.fn.maparg("<ScrollWheelUp>", "n")},
  })}, vim.env.NVIM_SCROLL_SMOKE_OUTPUT .. "/" .. name .. ".json")
end
vim.defer_fn(function() NvimScrollSnapshot("ready") end, 250)
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, help="configuration checkout to validate")
    parser.add_argument("--output", type=Path, help="new directory for JSON snapshots and terminal log")
    parser.add_argument("--nvim", default="nvim")
    args = parser.parse_args()
    root = (args.root or Path(__file__).resolve().parent.parent).resolve()
    output = args.output or Path(tempfile.mkdtemp(prefix="nvim-scroll-smoke-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    workspace = output / "workspace"
    workspace.mkdir()
    (workspace / ".root").write_text("")
    for name in ["first.lua", "second.lua"]:
        (workspace / name).write_text("".join(
            f'do local color_{index:04d} = "#abcdef" end\n' for index in range(1, 2001)))
    (output / "config").mkdir()
    (output / "config" / "nvim").symlink_to(root, target_is_directory=True)
    script = output / "snapshot.lua"
    script.write_text(SNAPSHOT)
    env = os.environ | {
        "TERM": "xterm-256color", "SHELL": "/bin/sh",
        "XDG_CONFIG_HOME": str(output / "config"), "NVIM_APPNAME": "nvim", "NVIM_CHECK_ONLY": "1",
        "XDG_CACHE_HOME": str(output / "cache"), "XDG_STATE_HOME": str(output / "state"),
        "NVIM_LOG_FILE": str(output / "nvim.log"), "NVIM_SCROLL_SMOKE_OUTPUT": str(output),
        "SSH_CONNECTION": "127.0.0.1 12345 127.0.0.1 22",
    }
    for variable in ["KITTY_WINDOW_ID", "WEZTERM_PANE", "TERM_PROGRAM"]:
        env.pop(variable, None)
    print(f"Scroll PTY evidence: {output}", flush=True)
    pid, master = pty.fork()
    if pid == 0:
        os.chdir(root)
        command = [args.nvim, "-u", str(root / "init.lua"), "-i", "NONE", str(workspace / "first.lua"),
                   "--cmd", "autocmd VimEnter * lua dofile(" + json.dumps(str(script)) + ")"]
        os.execvpe(command[0], command, env)
    columns, rows = 120, 36
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
    terminal_log = bytearray()
    snapshots = {}
    events = []
    query_replies = {
        b"\x1b]11;?": b"\x1b]11;rgb:1f1f/1f1f/1f1f\x1b\\",
        b"\x1b]10;?": b"\x1b]10;rgb:d4d4/d4d4/d4d4\x1b\\",
        b"\x1b[5n": b"\x1b[0n", b"\x1b[6n": b"\x1b[1;1R",
        b"\x1b[c": b"\x1b[?1;2c", b"\x1b[>c": b"\x1b[>0;0;0c",
        b"\x1bP$qm": b"\x1bP1$r0m\x1b\\",
    }
    query_pattern = re.compile(b"|".join(re.escape(query) for query in query_replies))
    query_buffer = b""
    query_tail = max(map(len, query_replies)) - 1

    def pump(duration=0.15):
        nonlocal query_buffer
        until = time.monotonic() + duration
        while time.monotonic() < until:
            readable, _, _ = select.select([master], [], [], min(0.05, max(0, until - time.monotonic())))
            if readable:
                try:
                    data = os.read(master, 65536)
                    if not data:
                        return
                    terminal_log.extend(data)
                    # Reply in terminal-output order, including the DSR status
                    # acknowledgement used to finish background-color probing.
                    # Retain a short suffix when an escape query spans reads.
                    query_buffer += data
                    end = 0
                    for match in query_pattern.finditer(query_buffer):
                        os.write(master, query_replies[match.group()])
                        end = match.end()
                    query_buffer = query_buffer[end:][-query_tail:]
                except OSError:
                    return

    def command(text):
        os.write(master, (":" + text + "\r").encode())
        pump()

    def snapshot(name, ready=False):
        if not ready:
            # Start the settling interval after Nvim has consumed the wheel
            # burst and this command. Waiting only on the PTY sender races the
            # queued color/scrollbar timers when terminal drawing is busy.
            command('lua vim.defer_fn(function() NvimScrollSnapshot("' + name + '") end, 150)')
        path = output / (name + ".json")
        deadline = time.monotonic() + 15
        while not path.exists() and time.monotonic() < deadline:
            pump(0.1)
        if not path.exists():
            raise RuntimeError(f"Terminal did not reach {name}: {output / 'terminal.log'}")
        state = json.loads(path.read_text())
        assert not state["errmsg"], f"Terminal error at {name}: {state['errmsg']}"
        assert not re.search(r"Error detected while processing|E\d{3,}:", state["messages"]), state["messages"]
        assert not state["neoscroll_loaded"], "Native wheel input unexpectedly loaded Neoscroll"
        snapshots[name] = state
        return state

    def window(state, winid=None):
        return next(win for win in state["windows"] if win["id"] == (winid or state["current"]))

    def wheel(win, direction, count):
        # SGR mouse coordinates are 1-based terminal cells. Use the middle of
        # the text area, away from gutters, floating bars and the status line.
        x = win["column"] + win["width"] // 2
        y = win["row"] + win["height"] // 2
        button = 65 if direction == "down" else 64
        sequence = f"\x1b[<{button};{x};{y}M".encode()
        events.append({"direction": direction, "count": count, "x": x, "y": y, "target": win["id"]})
        os.write(master, sequence * count)
        # A settling interval makes this a behavior check, not a latency probe.
        pump(0.3)

    def colors_visible(win):
        colored = {int(row) for row in win["color_rows"]}
        assert len(colored) >= 5, f"Colors are absent from the scrolled viewport: {win}"
        assert win["botline"] - 2 in colored, f"Newly visible bottom rows were not colored: {win}"

    def scrollbar(win):
        bar = win.get("scrollbar")
        assert bar and bar["count"] == 1, f"Expected one scrollbar for the text window: {win}"
        assert 1 <= bar["height"] <= win["height"], f"Invalid scrollbar height: {win}"
        assert 1 <= bar["row"] <= win["height"], f"Invalid scrollbar row: {win}"
        return bar

    def scrollbar_moved(before, after, direction):
        old, new = scrollbar(before), scrollbar(after)
        assert before["id"] == after["id"], "Compared scrollbars from different text windows"
        moved = new["row"] > old["row"] if direction == "down" else new["row"] < old["row"]
        assert moved, f"Scrollbar did not follow the {direction} viewport: before={before}, after={after}"

    def scrollbar_unchanged(before, after):
        old, new = scrollbar(before), scrollbar(after)
        assert (old["row"], old["height"]) == (new["row"], new["height"]), \
            f"Scrolling an inactive split moved the focused window's bar: before={before}, after={after}"

    def finish_process(graceful):
        # A failed assertion must not leave Nvim or its language servers alive.
        # Bound shutdown even when a plugin prevents a normal :qa! or SIGTERM.
        for sig, duration in [(None if graceful else signal.SIGTERM, 3), (signal.SIGTERM, 2)]:
            if sig:
                try:
                    os.killpg(pid, sig)
                except ProcessLookupError:
                    pass
            deadline = time.monotonic() + duration
            while time.monotonic() < deadline:
                ended, status = os.waitpid(pid, os.WNOHANG)
                if ended:
                    return os.waitstatus_to_exitcode(status)
                pump(0.05)
        try:
            os.killpg(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        _, status = os.waitpid(pid, 0)
        return os.waitstatus_to_exitcode(status)

    complete = False
    try:
        ready = snapshot("ready", ready=True)
        assert ready["colors_loaded"], "The Lua color fixture did not load color highlighting"
        colors_visible(window(ready))
        scrollbar(window(ready))
        # The rail has only about 30 rows for a 2,000-line fixture. Move far
        # enough in each direction to cross its quantization boundaries.
        wheel(window(ready), "down", 80)
        down = snapshot("down")
        assert window(down)["topline"] > window(ready)["botline"], "SGR wheel-down did not reveal new rows"
        scrollbar_moved(window(ready), window(down), "down")
        colors_visible(window(down))
        wheel(window(down), "up", 40)
        up = snapshot("up")
        assert window(up)["topline"] < window(down)["topline"], "SGR wheel-up did not scroll upward"
        scrollbar_moved(window(down), window(up), "up")
        colors_visible(window(up))

        command("vsplit")
        command('execute "edit " . fnameescape(' + json.dumps(str(workspace / "second.lua")) + ')')
        split = snapshot("split")
        active = window(split)
        hovered = next(win for win in split["windows"] if win["id"] != split["current"])
        wheel(hovered, "down", 80)
        inactive_down = snapshot("inactive_down")
        assert inactive_down["current"] == split["current"], "Wheel input stole focus from the current split"
        assert window(inactive_down)["topline"] == active["topline"], "The wrong split scrolled"
        assert window(inactive_down, hovered["id"])["topline"] > hovered["botline"], "Hovered split did not scroll"
        scrollbar_moved(hovered, window(inactive_down, hovered["id"]), "down")
        scrollbar_unchanged(active, window(inactive_down))
        colors_visible(window(inactive_down, hovered["id"]))
        wheel(window(inactive_down, hovered["id"]), "up", 40)
        inactive_up = snapshot("inactive_up")
        assert inactive_up["current"] == split["current"], "Wheel-up stole focus from the current split"
        assert window(inactive_up)["topline"] == active["topline"], "Wheel-up changed the wrong split"
        assert window(inactive_up, hovered["id"])["topline"] < window(inactive_down, hovered["id"])["topline"]
        scrollbar_moved(window(inactive_down, hovered["id"]), window(inactive_up, hovered["id"]), "up")
        scrollbar_unchanged(active, window(inactive_up))
        colors_visible(window(inactive_up, hovered["id"]))
        command("qa!")
        pump(0.2)
        complete = True
    finally:
        try:
            exit_code = finish_process(complete)
        finally:
            (output / "terminal.log").write_bytes(terminal_log)
            os.close(master)
    assert exit_code == 0, f"Neovim did not exit cleanly: {exit_code}"
    report = {
        "scope": "Actual xterm-256color PTY and SGR wheel bytes; verifies decoding, viewport, scrollview bar position/height, "
                 "split routing and color extmarks. "
                 "Does not measure physical mouse/trackpad latency, terminal frame rate or pixels.",
        "root": str(root), "columns": columns, "rows": rows, "events": events, "exit_code": exit_code,
        "checks": ["SGR wheel down", "SGR wheel up", "hovered inactive split without focus change",
                   "scrollview bar follows both wheel directions in focused and inactive windows",
                   "inactive-window scrolling preserves the focused window's bar",
                   "new visible color backgrounds", "wheel does not load Neoscroll", "no Neovim errors"],
        "snapshots": snapshots,
    }
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(output / "results.json")


if __name__ == "__main__":
    main()
