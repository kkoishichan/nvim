#!/usr/bin/env python3
"""Repeatable headless startup benchmark; uses installed plugins without updates."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import statistics
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=4, help="runs per scene; first is discarded")
    parser.add_argument("--output", type=Path, help="new directory for input files, logs and results.json")
    parser.add_argument("--nvim", default="nvim")
    args = parser.parse_args()
    if args.runs < 2:
        parser.error("--runs must be at least 2")
    root = Path(__file__).resolve().parent.parent
    output = args.output or Path(tempfile.mkdtemp(prefix="nvim-benchmark-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    samples = output / "samples"
    samples.mkdir()
    (samples / "small.lua").write_text("local answer = 42\nprint(answer)\n")
    (samples / "long.json").write_text('{"text":"' + "a" * 30000 + '"}\n')
    (samples / "large.json").write_text("[\n" + ",\n".join('"' + "a" * 98 + '"' for _ in range(26000)) + "\n]\n")
    result = {
        "method": "headless NVIM STARTED; fresh cache/state per run, installed data reused; discard first run",
        "scope": "Startup only. Does not measure screen drawing, completion, LSP readiness or external CLI startup.",
        "nvim": subprocess.check_output([args.nvim, "--version"], text=True).splitlines()[0],
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "working_tree_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True)),
        "lock_sha256": hashlib.sha256((root / "lazy-lock.json").read_bytes()).hexdigest(),
        "scenes": {},
    }
    for name, filename in {"empty": None, "small_lua": "small.lua", "long_json": "long.json", "large_json": "large.json"}.items():
        timings = []
        for index in range(args.runs):
            run = output / name / str(index + 1)
            run.mkdir(parents=True)
            (run / "config").mkdir()
            (run / "config" / "nvim").symlink_to(root, target_is_directory=True)
            env = os.environ | {
                "XDG_CONFIG_HOME": str(run / "config"), "NVIM_APPNAME": "nvim",
                "XDG_CACHE_HOME": str(run / "cache"), "XDG_STATE_HOME": str(run / "state"),
                "NVIM_LOG_FILE": str(run / "nvim.log"),
            }
            log = run / "startup.log"
            command = [args.nvim, "--headless", "-u", str(root / "init.lua"), "-i", "NONE",
                       "--startuptime", str(log), "--cmd",
                       'autocmd VimEnter * lua vim.defer_fn(function() '
                       'if vim.v.errmsg ~= "" then io.stderr:write("BENCH_STARTUP_ERROR: " .. vim.v.errmsg .. "\\n"); '
                       'vim.cmd("cquit 1") else vim.cmd("qa!") end end, 200)']
            if filename:
                command.append(str(samples / filename))
            with (run / "output.log").open("w") as stream:
                process = subprocess.Popen(command, cwd=root, env=env, stdout=stream, stderr=stream, start_new_session=True)
                try:
                    code = process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=5)
                    raise RuntimeError(f"Startup timed out: {run}") from None
            if code != 0:
                raise RuntimeError(f"Startup exited {code}: {run / 'output.log'}")
            messages = (run / "output.log").read_text(errors="replace")
            if re.search(r"BENCH_STARTUP_ERROR|Error detected while processing|E\d{3,}:|Failed to run.*config", messages):
                raise RuntimeError(f"Startup reported an error: {run / 'output.log'}")
            match = re.search(r"^\s*([\d.]+).*NVIM STARTED", log.read_text(), re.MULTILINE)
            if not match:
                raise RuntimeError(f"Startup milestone missing: {log}")
            timings.append(float(match.group(1)))
        median = statistics.median(timings[1:])
        result["scenes"][name] = {"runs_ms": timings, "median_ms": median}
        print(f"{name}: {median:.1f} ms ({timings})", flush=True)
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(output / "results.json")


if __name__ == "__main__":
    main()
