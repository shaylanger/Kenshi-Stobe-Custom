#!/usr/bin/env python3
"""Canonical entrypoint for the self-contained r4 invocation package."""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
R4 = HERE / "build-p0-final-invocation-r4.py"
spec = importlib.util.spec_from_file_location("p0_final_r4_builder", R4)
if not spec or not spec.loader:
    raise RuntimeError(f"cannot load r4 builder: {R4}")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def build(parent: Path) -> Path:
    return builder.build(parent)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parent", type=Path, help="new package parent; existing parents are rejected")
    print(build(parser.parse_args().parent))


if __name__ == "__main__":
    main()
