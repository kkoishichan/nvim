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


SCENES = {"empty": None, "small_lua": "small.lua", "medium_lua": "medium.lua",
          "long_json": "long.json", "large_json": "large.json"}


def metadata(root):
    return {
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip(),
        "working_tree_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=root, text=True)),
        "lock_sha256": hashlib.sha256((root / "lazy-lock.json").read_bytes()).hexdigest(),
    }


def measure(nvim, root, run, cache, sample):
    run.mkdir(parents=True)
    (run / "config").mkdir()
    (run / "config" / "nvim").symlink_to(root, target_is_directory=True)
    env = os.environ | {
        "XDG_CONFIG_HOME": str(run / "config"), "NVIM_APPNAME": "nvim",
        "NVIM_CHECK_ONLY": "1", "XDG_CACHE_HOME": str(cache),
        "XDG_STATE_HOME": str(run / "state"), "NVIM_LOG_FILE": str(run / "nvim.log"),
    }
    log = run / "startup.log"
    command = [nvim, "--headless", "-u", str(root / "init.lua"), "-i", "NONE",
               "--startuptime", str(log), "--cmd",
               'autocmd VimEnter * lua vim.defer_fn(function() '
               'if vim.v.errmsg ~= "" then io.stderr:write("BENCH_STARTUP_ERROR: " .. vim.v.errmsg .. "\\n"); '
               'vim.cmd("cquit 1") else vim.cmd("qa!") end end, 200)']
    if sample:
        command.append(str(sample))
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
    return float(match.group(1))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=4, help="runs per scene; first is discarded")
    parser.add_argument("--output", type=Path, help="new directory for input files, logs and results.json")
    parser.add_argument("--nvim", default="nvim")
    parser.add_argument("--root", type=Path, help="configuration checkout to measure; defaults to this repository")
    parser.add_argument("--baseline", type=Path,
                        help="compare this checkout with --root using alternating AB/BA order per scene")
    parser.add_argument("--scene", choices=SCENES, action="append",
                        help="scene to measure; repeat to select several (default: all)")
    parser.add_argument("--cache", choices=("cold", "warm"), default="cold",
                        help="cold: fresh cache per run; warm: reuse each scene's cache after first run")
    args = parser.parse_args()
    if args.runs < 2:
        parser.error("--runs must be at least 2")
    root = (args.root or Path(__file__).resolve().parent.parent).resolve()
    targets = {"current": root}
    if args.baseline:
        targets = {"baseline": args.baseline.resolve(), "current": root}
    output = args.output or Path(tempfile.mkdtemp(prefix="nvim-benchmark-"))
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    samples = output / "samples"
    samples.mkdir()
    (samples / "small.lua").write_text("local answer = 42\nprint(answer)\n")
    (samples / "medium.lua").write_text("local values = {}\n" + "".join(
        f"values[{index}] = {index}\n" for index in range(1, 2500)))
    (samples / "long.json").write_text('{"text":"' + "a" * 30000 + '"}\n')
    (samples / "large.json").write_text("[\n" + ",\n".join('"' + "a" * 98 + '"' for _ in range(26000)) + "\n]\n")
    result = {
        "method": f"headless NVIM STARTED; {args.cache} cache, fresh state per run, installed data reused; discard first run",
        "scope": "Startup only. Does not measure screen drawing, completion, LSP readiness or external CLI startup.",
        "nvim": subprocess.check_output([args.nvim, "--version"], text=True).splitlines()[0],
        "scenes": {},
    }
    if args.baseline:
        result["method"] += "; paired targets, alternating baseline/current and current/baseline each round"
        result["targets"] = {name: {"root": str(path), **metadata(path)} for name, path in targets.items()}
    else:
        # Preserve the original single-checkout JSON schema for existing reports.
        result.update(metadata(root))
    for name in dict.fromkeys(args.scene or SCENES):
        filename = SCENES[name]
        timings = {target: [] for target in targets}
        orders = []
        for index in range(args.runs):
            order = list(targets)
            if index % 2:
                order.reverse()
            orders.append(order)
            for target in order:
                target_output = output / target if args.baseline else output
                run = target_output / name / str(index + 1)
                cache = run / "cache" if args.cache == "cold" else target_output / name / "cache"
                timings[target].append(measure(args.nvim, targets[target], run, cache,
                                               samples / filename if filename else None))
        summaries = {target: {"runs_ms": values, "median_ms": statistics.median(values[1:])}
                     for target, values in timings.items()}
        if args.baseline:
            deltas = [current - baseline for current, baseline in zip(timings["current"], timings["baseline"])]
            result["scenes"][name] = {
                "targets": summaries, "order": orders,
                "paired_delta_ms": {"runs_ms": deltas, "median_ms": statistics.median(deltas[1:])},
            }
            print(f"{name}: baseline {summaries['baseline']['median_ms']:.1f} ms, "
                  f"current {summaries['current']['median_ms']:.1f} ms, "
                  f"paired delta {statistics.median(deltas[1:]):+.1f} ms", flush=True)
        else:
            result["scenes"][name] = summaries["current"]
            print(f"{name}: {summaries['current']['median_ms']:.1f} ms ({timings['current']})", flush=True)
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    print(output / "results.json")


if __name__ == "__main__":
    main()
