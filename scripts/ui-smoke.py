#!/usr/bin/env python3
"""Exercise actual terminal input and record Neovim window state in an isolated PTY."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import tempfile
import termios
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    output = args.output or Path(tempfile.mkdtemp(prefix="nvim-ui-smoke-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    print(f"UI evidence: {output}", flush=True)
    results = []
    for columns, rows in [(80, 24), (120, 36), (180, 50)]:
        run = output / f"{columns}x{rows}"
        workspace = run / "workspace"
        workspace.mkdir(parents=True)
        (workspace / ".root").write_text("")
        sample = workspace / "sample.txt"
        sample.write_text("sample\n")
        script = run / "snapshot.lua"
        script.write_text('''
function _G.NvimSmokeSnapshot(name)
  local windows = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    windows[#windows + 1] = {
      id = win, buffer = buf, width = vim.api.nvim_win_get_width(win), height = vim.api.nvim_win_get_height(win),
      filetype = vim.bo[buf].filetype, buftype = vim.bo[buf].buftype,
      role = require("user.core.window_roles").get(win),
      floating = vim.api.nvim_win_get_config(win).relative ~= "",
    }
  end
  vim.fn.writefile({ vim.json.encode({ windows = windows, current = vim.api.nvim_get_current_win(),
    mode = vim.api.nvim_get_mode().mode, errmsg = vim.v.errmsg, theme = vim.g.colors_name,
    completion_ms = _G.NvimSmokeCompletionMs }) },
    vim.env.NVIM_UI_SMOKE_OUTPUT .. "/" .. name .. ".json")
end
vim.defer_fn(function() NvimSmokeSnapshot("ready") end, 150)
''')
        env = os.environ | {
            "TERM": "xterm-256color", "SHELL": "/bin/sh",
            "XDG_CACHE_HOME": str(run / "cache"), "XDG_STATE_HOME": str(run / "state"),
            "NVIM_LOG_FILE": str(run / "nvim.log"), "NVIM_UI_SMOKE_OUTPUT": str(run),
        }
        # Simulate the no-image remote-terminal environment, without connecting
        # to an SSH server or using the user's terminal/browser sessions.
        env.pop("KITTY_WINDOW_ID", None)
        env.pop("WEZTERM_PANE", None)
        env.pop("TERM_PROGRAM", None)
        env["SSH_CONNECTION"] = "127.0.0.1 12345 127.0.0.1 22"
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(root)
            command = ["nvim", "-u", str(root / "init.lua"), "-i", "NONE", str(sample),
                       "--cmd", "autocmd VimEnter * lua dofile(" + json.dumps(str(script)) + ")"]
            os.execvpe(command[0], command, env)
        fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
        terminal_log = bytearray()

        def pump(duration=0.15):
            until = time.monotonic() + duration
            while time.monotonic() < until:
                readable, _, _ = select.select([master], [], [], min(0.05, max(0, until - time.monotonic())))
                if readable:
                    try:
                        data = os.read(master, 65536)
                        terminal_log.extend(data)
                        # Answer standard terminal queries so Nvim need not
                        # time out waiting for an absent graphical emulator.
                        for query, answer in [
                            (b"\x1b]11;?", b"\x1b]11;rgb:1f1f/1f1f/1f1f\x1b\\"),
                            (b"\x1b]10;?", b"\x1b]10;rgb:d4d4/d4d4/d4d4\x1b\\"),
                            (b"\x1b[6n", b"\x1b[1;1R"),
                            (b"\x1b[c", b"\x1b[?1;2c"),
                            (b"\x1b[>c", b"\x1b[>0;0;0c"),
                            (b"\x1bP$qm", b"\x1bP1$r0m\x1b\\"),
                        ]:
                            if query in data:
                                os.write(master, answer)
                    except OSError:
                        return

        def send(keys):
            os.write(master, keys if isinstance(keys, bytes) else keys.encode())
            pump()

        def command(text):
            send(":" + text + "\r")

        def snapshot(name, ready=False):
            if not ready:
                command('lua NvimSmokeSnapshot("' + name + '")')
            path = run / (name + ".json")
            deadline = time.monotonic() + 15
            while not path.exists() and time.monotonic() < deadline:
                pump(0.1)
            if not path.exists():
                raise RuntimeError(f"Terminal did not reach {name}: {run / 'terminal.log'}")
            result = json.loads(path.read_text())
            if result["errmsg"]:
                raise RuntimeError(f"Terminal error at {name}: {result['errmsg']}")
            return result

        def current(state):
            return next(win for win in state["windows"] if win["id"] == state["current"])

        try:
            snapshot("ready", ready=True)
            send(b"ismoke \x1b")
            send(" w")
            assert sample.read_text().startswith("smoke sample"), "Leader write did not save the typed text"
            command("vsplit")
            before = snapshot("split_before")
            send(b"\x1b[1;5D")  # Legacy xterm Ctrl-Left sequence.
            after = snapshot("split_after")
            assert current(after)["width"] < current(before)["width"], "Ctrl-Left did not resize the split"
            command("only")
            send(b"\x1f")  # Legacy terminals encode Ctrl-/ as Ctrl-_ / US.
            pump(0.4)
            send(b"\x1b")
            send(b"\x1b")
            opened = snapshot("terminal_open")
            assert any(win["buftype"] == "terminal" for win in opened["windows"]), "Ctrl-/ did not open a terminal"
            send(b"\x1f")
            closed = snapshot("terminal_closed")
            assert current(closed)["buftype"] == "", "Ctrl-/ did not return to editing"
            # Raw Alt-Space in Insert mode must enter Blink's manual completion.
            command("lua local cmp=require('blink.cmp'); _G.NvimSmokeShow=cmp.show; cmp.show=function(...) _G.NvimSmokeAlt=true; return true end")
            send(b"i\x1b \x1b")
            command("lua assert(_G.NvimSmokeAlt, 'Alt-Space was not decoded'); require('blink.cmp').show=_G.NvimSmokeShow")
            command("lua vim.api.nvim_buf_set_lines(0,0,-1,false,{'orchid_example orchid_expression','orc'}); vim.api.nvim_win_set_cursor(0,{2,2})")
            command("lua local cmp=require('blink.cmp'); cmp.show=function(...) _G.NvimSmokeStarted=vim.uv.hrtime(); return _G.NvimSmokeShow(...) end; local t=vim.uv.new_timer(); t:start(0,10,vim.schedule_wrap(function() if _G.NvimSmokeStarted and cmp.is_menu_visible() then _G.NvimSmokeCompletionMs=(vim.uv.hrtime()-_G.NvimSmokeStarted)/1e6; t:stop(); t:close(); NvimSmokeSnapshot('completion') end end))")
            send(b"A\x1b ")
            completion = snapshot("completion", ready=True)
            assert completion["completion_ms"] < 1000, "Buffer completion took over a second"
            send(b"\x1b")
            command("lua require('blink.cmp').show=_G.NvimSmokeShow")
            final = snapshot("complete")
            results.append({"columns": columns, "rows": rows, "checks": ["insert and leader write", "Ctrl-Left resize", "Ctrl-/ terminal", "Alt-Space completion dispatch", "real buffer completion menu"], "completion_ms": completion["completion_ms"], "state": final})
            command("qa!")
            pump(0.2)
        finally:
            (run / "terminal.log").write_bytes(terminal_log)
            try:
                ended, _ = os.waitpid(pid, os.WNOHANG)
                if not ended:
                    os.killpg(pid, signal.SIGTERM)
                    os.waitpid(pid, 0)
            except ProcessLookupError:
                pass
            os.close(master)
    report = {"scope": "Actual PTY with xterm-256color input; simulated SSH/no-image environment, not a live SSH host or graphical image protocol", "runs": results}
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(output / "results.json")


if __name__ == "__main__":
    main()
