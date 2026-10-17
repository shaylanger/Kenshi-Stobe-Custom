#!/usr/bin/env python3
"""stub_model.py - a fake "model" for testing run_point.py without calling anything.
Reads the prompt on stdin, answers with a fixed valid decision JSON (always: ignore). Prints a USAGE line on stderr.
  python run_point.py --points ... --cmd "python stub_model.py" --first 3 --out /tmp/stubrun
"""
import json, sys

prompt = sys.stdin.buffer.read().decode('utf-8', 'replace')
ans = {"event_class": "other",
       "decision": [{"type": "ignore", "exact_command_or_message": "stub: nothing", "why": "stub model, prompt had %d chars" % len(prompt)}],
       "checks": []}
sys.stdout.write("Here is my answer:\n" + json.dumps(ans) + "\n")
sys.stderr.write('USAGE {"in": %d, "out": 60, "cache_r": 0, "cache_w": 0}\n' % (len(prompt) // 4))
