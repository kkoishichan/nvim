import os
from pathlib import Path
import sys


def test_project_interpreter():
    assert Path(sys.prefix) == Path(__file__).parent / ".venv"


def test_intentional_outcome():
    assert os.environ.get("NVIM_WORKFLOW_FAIL") != "1"
