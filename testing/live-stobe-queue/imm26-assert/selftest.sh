#!/usr/bin/env bash
# Offline self-test of the imm26 assertion helpers. Part 1 runs every helper on EXISTING evidence bundles under
# C:\KenshiTestRuns\imm26-* with --lenient (missing hardened-only files are SKIPped; the old weak bundles are expected to FAIL
# the new strict checks, which is the point). Part 2 builds SYNTHETIC bundles (marked synth-) from real effects/prompt data to
# prove the PASS path. Prints RESULT lines only; never touches the game. Usage: bash selftest.sh   (Git Bash or WSL)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PY=$(command -v python3 || command -v python)
R=/c/KenshiTestRuns; [ -d "$R" ] || R=/mnt/c/KenshiTestRuns
S=$R/imm26-assert-selftest; rm -rf "$S"; mkdir -p "$S"
run() { "$PY" "$HERE/$1" "${@:2}" 2>&1 | cut -c1-420; }
x3() { echo "$1 $1 $1"; }

echo "## part 1: existing bundles (lenient)"
B=$R/imm26-4080; I=$R/imm26-4080-i4; J=$R/imm26-5090-i4/rows; K=$R/imm26-5090/rows; M=$R/imm26-5090-i5/rows3
run assert_stance.py 01-bx --target $(x3 $B/01-b) --ctl-nohist $(x3 $B/01-a-neg80) --ctl-pos $(x3 $B/01-a-aff60) --seed "Sure, a walk sounds good.|Fine, lead the way.|Count me in." --lenient
run assert_stance.py 01-cx --target $(x3 $M/IMM-01-c-hostile) --ctl $(x3 $M/IMM-01-c-ctl) --lenient
run assert_stance.py 16-bx --target $K/IMM-16-b-1 $K/IMM-16-b-2 $K/IMM-16-b-3 --ctl $K/IMM-16-b-1 $K/IMM-16-b-2 $K/IMM-16-b-3 --trait reserved --lenient
run assert_principle.py 02-ax --target $(x3 $B/02-a) --ctl $(x3 $M/IMM-01-c) --lenient
run assert_principle.py 02-bx --target $(x3 $M/IMM-02-b) --ctl $(x3 $M/IMM-02-c) --lenient
run assert_principle.py 02-cx --target $(x3 $M/IMM-02-c) --ctl $(x3 $M/IMM-01-c) --lenient
run assert_principle.py 02-dx --target $(x3 $M/IMM-02-d) --ctl $(x3 $M/IMM-02-b) --lenient
run assert_principle.py 05-cx --target $(x3 $B/05-c) --ctl $(x3 $B/01-a-neg80) --hidden $(x3 $B/05-c) --lenient
run assert_witness.py 03-cx --run $I/03-c-composed $I/03-c-composed-2 --victim Malzin --friend "Rel Vik" --ko "Rel Dax" --stranger "Rel Cee" --lenient
run assert_witness.py 04-ax --run $I/04-a-composed $I/04-a-composed-2 --victim "Rel Cee" --friend "Rel Vik" --stranger "Rel Fen" --lenient
run assert_witness.py 13-ax --pos $B/13-a-pay2 $B/13-a-pay2 --neg $B/13-a-breach $B/13-a-breach --ctl $B/13-a-accept2 --price 353 --lenient
run assert_witness.py 15-bx --out $(x3 $J/IMM-15-b) --inrange $(x3 $J/IMM-15-a) --fighters "Hungry Bandit,Habo" --starter Habo --lenient
run assert_claims.py 17-bx --false $(x3 $J/IMM-17-b) --true $(x3 $J/IMM-17-b) --item Sabreclaw --lenient
run assert_claims.py 18-cx --combat $(x3 $J/IMM-18-c) --calm $(x3 $J/IMM-18-a) --target Braddic --lenient
run assert_claims.py 19-ax --accept $J/IMM-19-a $J/IMM-19-a2 --recall $(x3 $J/IMM-19-a2) --ctl $(x3 $J/IMM-18-a) --dest "Stumble Inn" --lenient

echo "## part 2: synthetic bundles (PASS path + one expected FAIL)"
"$PY" - "$S" "$I" <<'EOF'
import os, shutil, sys
S, I = sys.argv[1], sys.argv[2]
def mk(name, src=None, **files):
    d = os.path.join(S, name); os.makedirs(d, exist_ok=True)
    if src:
        for f in os.listdir(src):
            shutil.copy(os.path.join(src, f), d)
    for k, v in files.items():
        open(os.path.join(d, k), 'w').write(v)
    return d
ids = "Rel Cee|2935424768\nRel Vik|263427728\nRel Fen|1767089792\nMalzin|2740478464\n"
for n in ('synth-04a-1', 'synth-04a-2'):
    mk(n, os.path.join(I, '04-a-composed-2'), **{'ids.txt': ids, 'haff.txt': 'Rel Vik->Rel Cee aff=60\n',
       'distance.txt': 'Rel Cee|10|drifters\nRel Vik|12|nomads\nRel Fen|12|drifters\n'})
for n in ('synth-03c-1', 'synth-03c-2'):
    mk(n, os.path.join(I, '03-c-composed-2'), **{'ids.txt': ids, 'distance.txt': 'Malzin|8|drifters\nRel Vik|12|nomads\nRel Fen|12|drifters\n'})

# chat-family synthetic bundles: prompt/events/inv written here (text is synthetic, structure copied from real bundles)
def chat(name, utter, reply, prompt_extra='', npc='Cind [Hungry Bandit]', **files):
    ev = "1|inputtext|Shay: %s (talking to: %s)|\n2|chat|Shay: %s (talking to: %s)|\n3|chat|%s: %s (talking to: Shay)|spoken\n" % (utter, npc, utter, npc, npc, reply)
    mk(name, **{'prompt.txt': prompt_extra, 'events.txt': ev, 'reply.txt': '', **files})
cl = '# Conversation History\nCind: You took my Sabreclaw.\n# World\n<claims_and_corrections>x</claims_and_corrections> you took my Sabreclaw'
for i, (u, r) in enumerate((("No, I never took your Sabreclaw.", "Then I was wrong to say you took it."), ("You are mistaken, I never touched it.", "Maybe I put it down somewhere; my mistake."), ("Check your pack, I haven't had it.", "Hm. I may have misplaced it. Sorry."))):
    chat('synth-17-f%d' % i, u, r, cl, **{'inv.txt': 'Sabreclaw|1\n'})
for i, (u, r) in enumerate((("No, I never took your Sabreclaw.", "Still, it is gone, and you were near my pack."), ("You've got it wrong, I did not touch it.", "But it is missing, so someone took it."), ("I haven't had your Sabreclaw.", "Then who did? It is not in my pack any more."))):
    chat('synth-17-t%d' % i, u, r, cl, **{'inv.txt': 'Bread|2\n'})
comb = 'Action Flags: in combat, attacking\n- Attack Target: Braddic [Hundred Guardian]\n'
for i, (u, r) in enumerate((("What's your target?", "Braddic, the big one."), ("Who are you fighting?", "That Braddic with the axe."), ("Are you in a fight right now?", "Yes, Braddic is on me."))):
    chat('synth-18-c%d' % i, u, r, comb, npc='Beak', **{'state.txt': 'in_combat=true target=Braddic\n'})
for i, (u, r) in enumerate((("What's your target?", "Nothing. Just standing here."), ("Who are you fighting?", "Nobody, all quiet."), ("Are you in a fight right now?", "No, not at the moment."))):
    chat('synth-18-k%d' % i, u, r, 'Condition: fine\n', npc='Beak', **{'state.txt': 'in_combat=false\n'})
# 13-ax: synthetic 5090-layout effects rows (select * layout) + state files
def eff(kind, delta, inc, obs='K'):
    js = '{"base": %d, "delta": %d, "total": %d, "reason": "known_outcome", "new_affinity": %d, "observer_name": "Cind", "culprit_name": "Shay"}' % (delta, delta, delta, delta)
    return "1\nabc%s|7|%s|e6:7:111|e6:7:222|%s|9000|%d|%s|t|phase8-v1\n" % ('0'*28, inc, kind, delta, js)
for i, (lab, kind, d, status, cats) in enumerate((('pos1', 'kept_promise', 2, 'COMPLETE', 'shay_before=1000 shay_after=647 npc_before=500 npc_after=853'),
        ('pos2', 'kept_promise', 3, 'COMPLETE', 'shay_before=900 shay_after=547 npc_before=10 npc_after=363'),
        ('neg1', 'broken_promise', -8, 'BREACHED_PLAYER', 'shay_before=1000 shay_after=1000 npc_before=500 npc_after=500'),
        ('neg2', 'broken_promise', -12, 'BREACHED_PLAYER', 'shay_before=900 shay_after=900 npc_before=10 npc_after=10'))):
    cid = 'deal-synth%d' % i
    mk('synth-13-' + lab, **{'effects.txt': eff(kind, d, 'deal:' + cid), 'deal.txt': 'contract=%s status=%s price=353\n' % (cid, status),
        'cats.txt': cats + '\n', 'haff_before.txt': 'aff=0\n', 'haff_after.txt': 'aff=%d\n' % d, 'save.txt': 'synth-save-%d\n' % i,
        'prompt.txt': '', 'events.txt': ''})
mk('synth-13-ctl', **{'effects.txt': '0\n', 'haff_before.txt': 'aff=0\n', 'haff_after.txt': 'aff=0\n', 'prompt.txt': '', 'events.txt': ''})
EOF
run assert_witness.py 04-ax --run $S/synth-04a-1 $S/synth-04a-2 --victim "Rel Cee" --friend "Rel Vik" --samefaction "Rel Fen"
run assert_witness.py 03-cx --run $S/synth-03c-1 $S/synth-03c-2 --victim Malzin --friend "Rel Vik"
echo "(expected FAIL below: 'Rel Fen' also got an aid row of equal size, so the stranger control is violated)"
run assert_witness.py 03-cx --run $S/synth-03c-1 $S/synth-03c-2 --victim Malzin --friend "Rel Vik" --stranger "Rel Fen"
run assert_witness.py 13-ax --pos $S/synth-13-pos1 $S/synth-13-pos2 --neg $S/synth-13-neg1 $S/synth-13-neg2 --ctl $S/synth-13-ctl --price 353
run assert_claims.py 17-bx --false $S/synth-17-f0 $S/synth-17-f1 $S/synth-17-f2 --true $S/synth-17-t0 $S/synth-17-t1 $S/synth-17-t2 --item Sabreclaw
run assert_claims.py 18-cx --combat $S/synth-18-c0 $S/synth-18-c1 $S/synth-18-c2 --calm $S/synth-18-k0 $S/synth-18-k1 $S/synth-18-k2 --target Braddic
rm -rf "$S"
