#!/usr/bin/env python3
"""imm26-huntA1 (Shay 2026-10-16): Hunt no-progress timeout + give-up line. SERVER side, anchored, CRLF-preserving, idempotent.
Usage (WSL): python3 apply.py <tree-root>      tree = the imm26 compose tree (needs wpE: ActivityLifecycle.php, claim policy in situated_dialogue.php)
  1. lib/activity/ActivityAgreementAdapter.php   noProgressTimeout 1800 -> 10000 game-s (5 min real at speed 1, ~10 min at speed 0.5)
  2. activity.php                                the terminal situated event of a FAILED report carries ending=failed
  3. lib/situated_dialogue.php                   ending=failed events are stored with the marker, rank as urgent (20 s / 40 s spacing,
                                                 priority 6, ttl 300 s) and the remark instruction tells the NPC to say it gives up and why
  4. tests/imm26_huntA_timeout_regression.php, tests/imm26_huntA_giveup_regression.php
The native DLL (NC27) asks for the targeted optional turn right after the server accepted the failed report; see NC27/README.md.
"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))

def load(p):
    s = open(p, encoding='utf-8', newline='').read()
    crlf = '\r\n' in s
    return (s.replace('\r\n', '\n') if crlf else s), crlf
def save(p, s, crlf):
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', '\r\n') if crlf else s)
def edit(rel, marker, pairs):
    p = os.path.join(root, rel)
    s, crlf = load(p)
    if marker in s:
        print(rel + ': already applied'); return
    for a, b in pairs:
        assert s.count(a) == 1, rel + ': anchor missing/duplicated: ' + a[:90]
        s = s.replace(a, b)
    save(p, s, crlf); print(rel + ': patched')

edit('lib/activity/ActivityAgreementAdapter.php', 'huntA1: no-progress', [(
"'noProgressTimeout' => 1800, 'agreedTargets' => $targets,",
"'noProgressTimeout' => 10000, /* huntA1: no-progress limit in GAME seconds: ~5 min real at speed 1, ~10 min at 0.5 (was 1800 = ~55 s) */ 'agreedTargets' => $targets,")])

edit('activity.php', "'ending'=>", [(
"'activity_id'=>$a['id'],'kind'=>$record['status']==='completed'?'completed':'plan_changed',",
"'activity_id'=>$a['id'],'kind'=>$record['status']==='completed'?'completed':'plan_changed',\n                'ending'=>$record['status']==='failed'?'failed':'',")])

INSTRUCTION = (
"function stobeSituatedRemarkInstruction(array $event): string {\n"
"    $text=stobeSituatedRemarkInstructionBase($event);\n"
"    if (($event['ending']??'')==='failed') $text.=\"\\nThis observation is the end of the job you agreed to do with this person, and it did not succeed. \"\n"
"        .\"Say, in your own voice and in one or two short sentences, that you are giving up on it for now and why, using the reason in the observation \"\n"
"        .\"(put it in your own words, for example that you cannot find anything to hunt). Do not promise to keep trying and do not start, cancel or change anything.\";\n"
"    return $text;\n}\n\n"
"function stobeSituatedRemarkInstructionBase(array $event): string {\n")

edit('lib/situated_dialogue.php', 'huntA1: ending', [
("        'kind'=>$kind,'fact'=>$fact,'recorded_unix'=>time()];\n",
 "        'kind'=>$kind,'fact'=>$fact,'recorded_unix'=>time()];\n    if (($event['ending']??'')==='failed') $payload['ending']='failed'; // huntA1: ending\n"),
("            $policy=stobeSituatedKindPolicy(strval($event['kind']??''));\n            $age=",
 "            $policy=stobeSituatedKindPolicy(strval($event['kind']??''));\n"
 "            // huntA1: a FAILED job must be told at once (the NPC says it gives up and why): urgent spacing, top rank, 5 min validity.\n"
 "            if (($event['ending']??'')==='failed') $policy=['ttl'=>300,'priority'=>6,'urgent'=>true];\n            $age="),
("function stobeSituatedRemarkInstruction(array $event): string {\n", INSTRUCTION),
])

os.makedirs(os.path.join(root, 'tests'), exist_ok=True)
for t in ('imm26_huntA_timeout_regression.php', 'imm26_huntA_giveup_regression.php'):
    shutil.copyfile(os.path.join(here, 'tests', t), os.path.join(root, 'tests', t)); print('tests/' + t + ': copied')
