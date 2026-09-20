#!/usr/bin/env python3
"""Regression checks for isolated input files and benchmark sample integrity."""

import ast
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest


BENCH = runpy.run_path(str(Path(__file__).with_name("benchmark-mode.py")))


class Samples(unittest.TestCase):
    def test_independent_copies_and_valid_saves(self):
        with tempfile.TemporaryDirectory(prefix="nvim-benchmark-check-") as directory:
            root = Path(directory)
            source = root / "real source.py"
            original = b'"""Original source."""\ndef example(value: int):\n    return value + 1\n'
            source.write_bytes(original)
            source.chmod(0o400)
            alias = root / "linked.py"
            alias.symlink_to(source)
            first = BENCH["copy_sample"](alias, root / "first")
            second = BENCH["copy_sample"](alias, root / "second")
            self.assertFalse(first.is_symlink())
            first.write_text("invalid first run\n")
            self.assertEqual(source.read_bytes(), original)
            self.assertEqual(second.read_bytes(), original)

            script = root / "check.lua"
            script.write_text(
                'vim.cmd.edit(vim.fn.fnameescape(vim.env.TEST_SAMPLE))\n'
                + BENCH["PROBE"]
                + '\nvim.api.nvim_buf_set_lines(0, 0, -1, false, { "invalid typing" })\n'
                + 'BenchSave(2)\nvim.cmd("qa!")\n'
            )
            env = os.environ | {
                "XDG_STATE_HOME": str(root / "state"),
                "XDG_CACHE_HOME": str(root / "cache"),
                "NVIM_LOG_FILE": str(root / "nvim.log"),
                "BENCH_RUN": str(root),
                "BENCH_SETTLE_MS": "60000",
                "TEST_SAMPLE": str(second),
            }
            subprocess.run(
                ["nvim", "--headless", "-u", "NONE", "-n", "-i", "NONE", "-l", str(script)],
                env=env, check=True, capture_output=True, timeout=15,
            )
            self.assertEqual(len(json.loads((root / "save.json").read_text())), 2)
            self.assertEqual(source.read_bytes(), original)
            self.assertEqual(second.read_bytes(), original)
            ast.parse(second.read_text())


if __name__ == "__main__":
    unittest.main()
