#!/usr/bin/env python3
"""Measure mapped page keys through the final viewport's Neovim UI flush.

Includes configured animations and full highlighting, but excludes terminal and
hardware latency. Reads --file without saving it. Requires Python msgpack.
"""

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import statistics
import subprocess
import sys
import tempfile
import time


# Import the shared RPC driver without leaving generated files in the checkout.
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "scroll_benchmark", Path(__file__).with_name("benchmark-scroll.py")
)
scroll = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scroll)


def highlight_snapshot(editor):
    """Fingerprint captures and resolved colors outside the timed samples."""
    captures = editor.call(
        "nvim_exec_lua",
        """
      local buf = vim.api.nvim_get_current_buf()
      assert(vim.treesitter.highlighter.active[buf], 'Tree-sitter highlighting is required')
      local parser = vim.treesitter.get_parser(buf)
      parser:parse()
      local captures = {}
      parser:for_each_tree(function(tree, langtree)
        local lang = langtree:lang()
        local query = vim.treesitter.query.get(lang, 'highlights')
        if not query then return end
        for id, node, metadata in query:iter_captures(tree:root(), buf, 0, -1) do
          local name = query.captures[id]
          -- Resolve every capture, including offscreen groups that the
          -- highlighter would otherwise initialize only after scrolling.
          local hl = vim.api.nvim_get_hl_id_by_name('@' .. name .. '.' .. lang)
          captures[#captures+1] = {lang=lang, name=name, range={node:range()}, metadata=metadata,
            highlight=vim.api.nvim_get_hl(0, {id=hl, link=false})}
        end
      end)
      return captures
    """,
        [],
    )
    normalized = json.dumps(captures, sort_keys=True, separators=(",", ":"))
    return {
        "captures": len(captures),
        "sha256": hashlib.sha256(normalized.encode()).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--nvim", default="nvim")
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--samples", type=int, default=6)
    args = parser.parse_args()
    if args.runs < 1 or args.samples < 2:
        parser.error("Use at least one run and two samples")
    source = args.file.expanduser().resolve()
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    root = Path(__file__).resolve().parent.parent
    targets = {"baseline": args.baseline.resolve()} if args.baseline else {}
    targets["current"] = root
    output = args.output or Path(tempfile.mkdtemp(prefix="nvim-navigation-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    report = {
        "scope": __doc__,
        "file": str(source),
        "source_sha256": digest,
        "nvim": subprocess.check_output(
            [args.nvim, "--version"], text=True
        ).splitlines()[0],
        "targets": {name: scroll.metadata(path) for name, path in targets.items()},
        "results": {name: [] for name in targets},
    }
    for run in range(args.runs):
        order = list(targets) if run % 2 == 0 else list(reversed(targets))
        for name in order:
            editor = scroll.Editor(
                targets[name], output / name / str(run), source, args.nvim
            )
            try:
                editor.call(
                    "nvim_exec_lua",
                    """
                  assert(vim.fn.line('$') >= 150, 'Use a file with at least 150 lines')
                  _G.NavProbeState = function()
                    return {vim.fn.line('w0'), vim.api.nvim_win_get_cursor(0)}
                  end
                  vim.api.nvim_create_autocmd({'WinScrolled', 'CursorMoved'}, {callback=function()
                    if NavProbeTarget and vim.deep_equal(NavProbeState(), NavProbeTarget) then
                      NavProbeTarget = nil
                      vim.rpcnotify(1, 'navigation_probe')
                    end
                  end})
                """,
                    [],
                )
                highlights = highlight_snapshot(editor)
                rows = {}
                for key in ("<C-d>", "<C-f>"):

                    def reset():
                        editor.call("nvim_exec_lua", "vim.cmd('normal! 70Gzz')", [])
                        editor.drain(0.2)

                    # Let the real mapping choose its destination and finish;
                    # no animation callbacks or redraw functions are replaced.
                    reset()
                    editor.call("nvim_input", key)
                    editor.drain(1)
                    target = editor.call("nvim_exec_lua", "return NavProbeState()", [])
                    samples = []
                    for _ in range(args.samples):
                        reset()
                        editor.call("nvim_exec_lua", "NavProbeTarget = ...", [target])
                        editor.drain(0.02)
                        start = time.perf_counter()
                        editor.call("nvim_input", key)
                        reached = False
                        while time.perf_counter() - start < 5:
                            message = (
                                editor.notifications.popleft()
                                if editor.notifications
                                else editor.next(5)
                            )
                            if message[0] != 2:
                                continue
                            if message[1] == "navigation_probe":
                                reached = True
                            if (
                                reached
                                and message[1] == "redraw"
                                and any(x[0] == "flush" for x in message[2])
                            ):
                                samples.append((time.perf_counter() - start) * 1000)
                                break
                        else:
                            raise TimeoutError(
                                f"{name} {key} did not reach its settled viewport"
                            )
                        editor.drain(0.1)
                    rows[key] = {
                        "destination": target,
                        "samples_ms": samples,
                        "p50_ms": statistics.median(samples),
                        "p95_ms": sorted(samples)[math.ceil(len(samples) * 0.95) - 1],
                    }
                conditions = editor.call(
                    "nvim_exec_lua",
                    """
                  return {treesitter_active=vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]~=nil,
                    syntax=vim.bo.syntax, neoscroll_loaded=package.loaded.neoscroll~=nil, modified=vim.bo.modified}
                """,
                    [],
                )
                assert not conditions["modified"], (
                    "Benchmark modified the source buffer"
                )
                assert highlight_snapshot(editor) == highlights, (
                    "Navigation changed highlight captures or colors"
                )
                report["results"][name].append(
                    {"keys": rows, "conditions": conditions, "highlights": highlights}
                )
                print(
                    name,
                    run,
                    {key: round(row["p50_ms"], 2) for key, row in rows.items()},
                    flush=True,
                )
            finally:
                editor.close()
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest, (
        "Source file changed during benchmark"
    )
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(output / "results.json")


if __name__ == "__main__":
    main()
