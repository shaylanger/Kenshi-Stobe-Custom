#!/usr/bin/env python3
"""Canonical selftest entrypoint; executes the packaging-only r4 selftest."""
from pathlib import Path
import runpy

HERE = Path(__file__).resolve().parent
runpy.run_path(str(HERE / "test-p0-final-invocation-r4.py"), run_name="__main__")
