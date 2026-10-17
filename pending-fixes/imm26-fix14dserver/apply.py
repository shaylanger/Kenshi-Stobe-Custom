#!/usr/bin/env python3
"""imm26 fix14dserver (row 14-d): the ClearGroup activity_intent shape is spelled out in the activity prompt.
Row 14-d (imm26-5090-i5-op21, req_6ad2e2f8eadf4): the LLM proposed ClearGroup with the right 5 agreedTargets but wrote
  {"kind":"ClearGroup","sourceId":..,"targetSerial":526123040,"discoveryRef":"activity-proposal:..:27","campZoneRef":{..},"agreedTargets":[..]}
i.e. targetSerial as a TOP-LEVEL field, discoveryRef as a bare STRING, and no routeRef. The adapter was right to reject it
('Unexpected activity fields'): campZoneRef is ALREADY in the allowlist (as an object {candidateId,scopeDigest}) and the adapter is NOT changed.
The wrong side is the prompt: "discoveryRef candidateId/targetSerial for the activity source" never says the two belong INSIDE an object.
This patch only rewrites that clause in lib/activity/activity_prompt.php: discoveryRef / routeRef / campZoneRef are named as OBJECTS with
their exact keys, plus one complete ClearGroup example (no quantity). Validation is unchanged (unknown keys, string discoveryRef still reject).
usage: python3 apply.py <tree-root> [--check]   (idempotent; asserts anchors; writes *.bak-fix14dserver)
"""
import sys, shutil, os
root = sys.argv[1]; check = '--check' in sys.argv
PF = os.path.join(root, 'lib/activity/activity_prompt.php')
MARK = 'fix14dserver'

A1 = ("discoveryRef candidateId/targetSerial for the activity source, routeRef containing only candidateId selected from the separate observed routeCandidates list, "
      "and fixed agreedTargets (only ClearGroup). For a ClearGroup proposal whose selected observed source has campZone candidateId and scopeDigest, "
      "copy both unchanged into campZoneRef; never invent, edit, or substitute those values.")
N1 = ("discoveryRef = an OBJECT {\"candidateId\":\"<id>\",\"targetSerial\":<number>} for the activity source (both keys go INSIDE discoveryRef, never as top-level fields and never a bare string), "
      "routeRef = an OBJECT containing only candidateId selected from the separate observed routeCandidates list (always required), "
      "and fixed agreedTargets (only ClearGroup). For a ClearGroup proposal whose selected observed source has campZone candidateId and scopeDigest, "
      "copy both unchanged into campZoneRef = an OBJECT {\"candidateId\":\"<v1:...>\",\"scopeDigest\":\"<hex>\"}; never invent, edit, or substitute those values. "
      "Complete ClearGroup activity_intent example (the only top-level fields are kind, sourceId, discoveryRef, routeRef, campZoneRef, agreedTargets; no quantity): "
      "{\"kind\":\"ClearGroup\",\"sourceId\":\"<source id>\",\"discoveryRef\":{\"candidateId\":\"<id>\",\"targetSerial\":<n>},\"routeRef\":{\"candidateId\":\"<route id>\"},"
      "\"campZoneRef\":{\"candidateId\":\"<v1:...>\",\"scopeDigest\":\"<hex>\"},\"agreedTargets\":[<serial>,<serial>]}.")
# the PHP source is a single-quoted string: the new text must not contain a single quote
assert "'" not in N1

s = open(PF, encoding='utf-8', newline='').read()
if N1 in s:
    print('already patched:', PF); sys.exit(0)
assert s.count(A1) == 1, 'anchor count %d' % s.count(A1)
if check:
    print('anchor ok:', PF); sys.exit(0)
shutil.copy2(PF, PF + '.bak-' + MARK)
open(PF, 'w', encoding='utf-8', newline='').write(s.replace(A1, N1))
print('patched:', PF)
