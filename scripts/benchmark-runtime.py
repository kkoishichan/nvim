#!/usr/bin/env python3
"""Compare isolated editing, UI callback and tool lookup costs against a checkout.

These measurements are synchronous Lua/API costs, not end-to-end keystroke latency.
Uses only installed Neovim and local fixtures; never downloads or updates plugins.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile


def revision(root):
    return {
        "path": str(root),
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True)),
        "lock_sha256": hashlib.sha256((root / "lazy-lock.json").read_bytes()).hexdigest(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, help="frozen checkout to compare using the same benchmark scripts")
    parser.add_argument("--output", type=Path, help="new output directory")
    parser.add_argument("--nvim", default="nvim")
    parser.add_argument("--iterations", type=int, default=300, help="input/delete pairs per editing scene")
    args = parser.parse_args()
    if args.iterations < 20:
        parser.error("--iterations must be at least 20")
    root = Path(__file__).resolve().parent.parent
    output = args.output or Path(tempfile.mkdtemp(prefix="nvim-runtime-benchmark-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    targets = {}
    if args.baseline:
        targets["baseline"] = args.baseline.resolve()
    targets["current"] = root
    report = {
        "scope": "Isolated synchronous core callbacks; excludes full rendering, plugins, language servers and external tools. See each scene's scope.",
        "nvim": subprocess.check_output([args.nvim, "--version"], text=True).splitlines()[0],
        "targets": {name: revision(path) for name, path in targets.items()},
        "results": {name: {} for name in targets},
    }
    for group in ("context", "editing", "ui"):
        for name, config in targets.items():
            run = output / name / group
            (run / "config" / "nvim").mkdir(parents=True)
            for entry in ("init.lua", "lua", "after", "spell", "lazy-lock.json"):
                (run / "config" / "nvim" / entry).symlink_to(config / entry)
            result = run / "result.json"
            env = os.environ | {
                "XDG_CONFIG_HOME": str(run / "config"), "NVIM_APPNAME": "nvim",
                "XDG_CACHE_HOME": str(run / "cache"), "XDG_STATE_HOME": str(run / "state"),
                "NVIM_LOG_FILE": str(run / "nvim.log"), "NVIM_CHECK_ONLY": "1",
                "NVIM_BENCH_ROOT": str(config), "NVIM_BENCH_TMP": str(run),
                "NVIM_BENCH_OUTPUT": str(result), "NVIM_BENCH_ITERATIONS": str(args.iterations),
            }
            command = [args.nvim, "--headless", "-u", "NONE", "-i", "NONE", "-l",
                       str(root / "scripts" / "benchmarks" / (group + ".lua"))]
            with (run / "output.log").open("w") as stream:
                process = subprocess.Popen(command, cwd=config, env=env, stdout=stream, stderr=stream,
                                           start_new_session=True)
                try:
                    code = process.wait(timeout=120)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=5)
                    raise RuntimeError(f"Benchmark timed out: {run}") from None
            if code != 0 or not result.exists():
                raise RuntimeError(f"Benchmark failed ({code}): {run / 'output.log'}")
            report["results"][name][group] = json.loads(result.read_text())
            print(f"{name} {group}: {result}", flush=True)
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(output / "results.json")


if __name__ == "__main__":
    main()
