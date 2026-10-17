#!/usr/bin/env python3
"""answer_from_dir.py - feed answers you collected BY HAND (e.g. from a chat window) back through run_point.py.
  python answer_from_dir.py <prompt-file> <answers-dir>
Prints <answers-dir>/<point id>.txt, where the point id (P001...) is taken from the prompt file name. Use it as the --cmd of run_point.py:
  python tools/run_point.py --points data/replay/points --cmd "python tools/answer_from_dir.py {PROMPT_FILE} my_answers" --out runs/LABEL ...
Missing answer file -> empty output -> that point is recorded as a failure (as it should be).
"""
import os, sys
pid = os.path.splitext(os.path.basename(sys.argv[1]))[0]
fn = os.path.join(sys.argv[2], pid + '.txt')
if os.path.exists(fn):
    sys.stdout.buffer.write(open(fn, 'rb').read())
