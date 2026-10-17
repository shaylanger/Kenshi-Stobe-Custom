#!/usr/bin/env python3
"""selftest_01cx.py (imm26-fix01cx): offline proof of v3cx/assert_stance.py (row 01-cx).  Synthetic bundles only (no game, no lane, no stored evidence needed);
the 'real' cases embed the actual replies of the 6 stored 4080-i3 op30 runs (rep r1..r3, savA/savB) and must PASS; mutations must FAIL as stated.
Prints `SELFTEST 01cx-<name> PASS|FAIL ...` and `SELFTEST 01CX ALL PASS|FAIL n/m`.   Usage: python -I selftest_01cx.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
AS = os.path.join(HERE, 'assert_stance.py')
V2 = os.path.join(HERE, '..', 'v2', 'assert_stance.py')
TMP = tempfile.mkdtemp(prefix='fix01cx-')
N = [0, 0]
GREET = ['Hello there.', 'Good day to you.', 'Who are you people?']
HP = ('known_relationship&quot;:false} First contact, no personal history: your people are enemies of theirs. Open guarded or hostile in your own voice. '
      'Opening rule: your first sentence must already carry the unfriendliness.')
AP = 'known_relationship&quot;:false} You share a faction bond with this stranger (allied).'


def mk(root, label, kind, greet, replies, rel, to='Shay', status='spoken'):
    d = os.path.join(root, label)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'prompt.txt'), 'w', encoding='utf-8').write(HP if kind == 'H' else AP)
    open(os.path.join(d, 'faction_rel.txt'), 'w').write(f'rel={rel}\nlistener_faction=X player_faction=Nameless\n')
    rows = [f'100|inputtext|Shay: {greet} (talking to: Npc)|', f'101|chat|Shay: {greet} (talking to: Npc)|']
    for i, r in enumerate(replies):
        rows.append(f'{110 + i}|chat|Npc: {r} (talking to: {to})|{status}')
    open(os.path.join(d, 'events.txt'), 'w', encoding='utf-8').write('\n'.join(rows) + '\n')
    return d


def build(root, H, A, hrel, arel, hkw=None, akw=None):
    hd = [mk(root, f'H{i + 1}', 'H', GREET[i], H[i], hrel, **(hkw or {})) for i in range(3)]
    ad = [mk(root, f'A{i + 1}', 'A', GREET[i], A[i], arel, **(akw or {})) for i in range(3)]
    return hd, ad


def result_line(script, hd, ad, flags=()):
    p = subprocess.run([sys.executable, '-I', script, '01-cx', '--target'] + hd + ['--ctl'] + ad + list(flags), capture_output=True, text=True)
    ln = [x for x in p.stdout.splitlines() if x.startswith('RESULT')]
    return ln[-1] if ln else 'RESULT NO-RESULT ERR ' + p.stderr[-300:]


def run(name, H, A, hrel=-100, arel=70, want='PASS', must=None, flags=(), hkw=None, akw=None):
    hd, ad = build(os.path.join(TMP, name), H, A, hrel, arel, hkw, akw)
    line = result_line(AS, hd, ad, flags)
    v = line.split()[2]
    ok = v == want and (must is None or must in line)
    N[1] += 1
    N[0] += ok
    print(f'SELFTEST 01cx-{name} {"PASS" if ok else "FAIL"} want={want}{"/" + must if must else ""} got={v} {"" if ok else line[:200]}')


def run_v2(name, H, A, want):
    """the v2 verdict on the same synthetic bundles: documents the defect (and that v2 is unchanged)."""
    hd, ad = build(os.path.join(TMP, name + '-v2'), H, A, -100, 70)
    v = result_line(V2, hd, ad).split()[2]
    N[1] += 1
    N[0] += v == want
    print(f'SELFTEST 01cx-{name}-v2-contrast {"PASS" if v == want else "FAIL"} v2 verdict={v} (expected {want})')


# the actual replies of the stored evidence (4080-i3 op30, imm26-4080-rep/01-cx-r1..r3): per greeting a list of utterances (chat rows)
REAL = {
    'r1savA': ([["Don't have anything for you, stranger - unless you're buying, in which case we can talk price.", "Otherwise keep your distance; I don't know you and I'd rather keep it that way."],
                ["Day's only good if you keep breathing through it. What do you want?"],
                ["Slave Hunters. That's the answer you're owed, and it's the only one you get for free.", "If you're looking to get chained, keep standing there."]],
               [["Morning. You're up early, or late - hard to tell out here. What brings you over?"],
                ["Morning. Calm enough out here - good time to be moving before the dust kicks up. What brings you to the Hub?"],
                ["Just a traveler, same as most folks out here. Name's Brethar - some call me Captain Rukni.", "I keep to myself and my training mostly, but I don't bite. What brings you to the Hub?"]]),
    'r1savB': ([["Hm. You're standing in the open, talking to a stranger at dawn. Either you're new, or you're bait. Which is it?"],
                ["Morning. You'll want to keep your distance - I'm not in the habit of chatting with strangers in the Hub.", "Say what you need, and I'll decide if it's worth my time."],
                ["Slave Hunters. That's the short answer, and it's the only part that matters to a stranger.", "If you're looking for a name to trust, keep walking - I don't hand those out to people I just met."]],
               [["Morning. Brethar - folks around here just call me Captain Rukni if it suits them.", "You're up early, same as me. What brings you out this way?"],
                ["Morning. You're up early - most folk in the Hub are still face-down in the dirt this hour. What brings you out here?"],
                ["Just a traveler passing through, same as most folk in the Hub. Name's Brethar.", "You look like you've got questions - ask them plain and I'll answer what I can."]]),
    'r2savA': ([["You're standing in my shadow and I don't know you.", "So unless you've got business - a name, a reason, or a road worth walking - I'd keep my distance and you keep yours."],
                ["If you're selling something, say it plain.", "If you're just passing the morning, keep walking - I don't settle into conversation with strangers before I've counted the", "ways out of it."],
                ["People who work. Slave Hunters, if the name means anything to you.", "If you're looking for a fight or a favour, I've got neither - I'm just passing through The Hub same as anyone with sense."]],
               [["Morning. If you're looking for trade, I've got medical supplies and a kit, but I don't hand them out for free."],
                ["Morning. Not much of one yet, but I'll take it."],
                ["Abia. I patch wounds and I travel light. That's about the whole of it."]]),
    'r2savB': ([["Don't know you. Don't much care to, either. If you've got business, state it quick and keep your hands where I can see them."],
                ["Day's barely started and you're already talking at strangers.", "State your business or move along - I'm not standing still long."],
                ["That's a question with teeth in it, so here's the short of it: I'm Ahualpa, and I work with the Slave Hunters - not for you, not against you, unless you give me a reason.",
                 "I count exits before I count friends, and I don't hand out my name to strangers who ask like it's owed. So.", "Who's asking?"]],
               [["Morning. If you're after something, say it plain - I'm not one for standing around."],
                ["Good day. What do you need?"],
                ["Outlaws, mostly. Holy Nation Outlaws, if you want the whole name. I'm Abia.", "I patch wounds and keep my head down, same as most here."]]),
    'r3savA': ([["Hm. You're standing there talking to a Slave Hunter like it's nothing.", "Either you don't know what that means, or you don't care. Either way, I'd rather know which before I say anything else."],
                ["Day's fine enough.", "But you're standing close for someone I don't know, so say what you want and keep your hands where I can see them."],
                ["If you're asking who I run with, that's the Slave Hunters. If you're asking who I am - someone passing through, same as you.", "Don't read more into it than that."]],
               [["Morning. You're up early - or maybe you never went down. Either way, good time to be moving."],
                ["Morning. You're up early, or late - hard to tell out here. I'm Brethar. Folks call me Captain when they're being polite.", "What brings you through the Hub?"],
                ["Just a hiver with a stick and a long walk behind him.", "Name's Brethar - some call me Captain Rukni, though I don't much care which sticks. And you?", "You've got the look of someone deciding who to trust out here."]]),
    'r3savB': ([["Keep your distance. I don't know you, and I don't care to. Say your piece from there or move along."],
                ["Day's only good if you keep your distance. State your business and keep your hands where I can see them."],
                ["We're Slave Hunters.", "That's enough for you to know - you're not one of ours, so keep your distance and we won't have a problem."]],
               [["Morning. You're up early - most folk in the Hub are still arguing with their bedrolls.", "Something on your mind, or just passing the time?"],
                ["Morning. Quiet one so far - good time to be moving before the heat and the patrols wake up."],
                ["Us? Just a hiver with a stick and a bad habit of staying alive.", "Name's Brethar - some folks call me Captain Rukni, though I don't push the title.",
                 "And you're standing in the Hub, same as me, so I figure we're both just trying to get by."]]),
}
for k, (h, a) in REAL.items():
    run('real-' + k, h, a, want='PASS')

H_OK, A_OK = REAL['r3savB']
A_OPEN = REAL['r1savA'][1]
# ---- mutations: hostile side
FRIENDLY = [["Hello there, friend! Welcome to the Hub. What can I do for you?"], ["Good day to you too! Glad to see a new face - how can I help?"], ["We're a friendly bunch, welcome! Name's Brethar, nice to meet you."]]
run('mut-hostile-friendly', FRIENDLY, A_OPEN, want='FAIL', must='hostile_guarded>=2/3!')
OPEN_STIFF = [["Welcome, friend! Though keep your distance from the cages."], ["Glad to meet you, good day! Keep your hands where I can see them, ha."], ["Well met! Slave Hunters, and you're not one of ours, so don't linger."]]
run('mut-hostile-but-open-with-stiff-phrase', OPEN_STIFF, A_OPEN, want='FAIL', must='hostile_guarded>=2/3!')
CURT_NEUTRAL = [["Morning."], ["Hm."], ["Fine day. Just passing through, same as you."]]
run('mut-hostile-neutral-curt', CURT_NEUTRAL, A_OPEN, want='FAIL', must='hostile_guarded>=2/3!')
ONE_OF_3 = [H_OK[0], ["Good day. What brings you to the Hub?"], ["Just a traveler. Name's Brethar, nice enough place if you like dust."]]
run('mut-hostile-1of3-guarded', ONE_OF_3, A_OPEN, want='FAIL', must='hostile_guarded>=2/3!')
run('mut-hostile-empty-reply', [[], [], []], A_OPEN, want='FAIL', must='hostile_guarded>=2/3!')
TWO_PLUS_WARM = [H_OK[0], H_OK[1], ["Welcome, friend! Glad you stopped by - how can I help?"]]
run('mut-hostile-2guarded-1-warm-gate', TWO_PLUS_WARM, A_OPEN, want='FAIL', must='hostile_not_open!')
run('mut-hostile-chatter-only', H_OK, A_OPEN, want='FAIL', must='hostile_guarded>=2/3!', hkw=dict(to='Malzin'))
run('mut-hostile-cancelled-rows', H_OK, A_OPEN, want='FAIL', must='hostile_guarded>=2/3!', hkw=dict(status='cancelled'))
run('mut-hostile-rel-minus20', H_OK, A_OPEN, hrel=-20, want='FAIL', must='faction_rel!')
# ---- mutations: allied side
ALLIED_GUARDED = [["Keep your distance. I don't know you."], ["State your business and move along."], ["Hello. We're not friends; keep your hands where I can see them."]]
run('mut-allied-guarded', H_OK, ALLIED_GUARDED, want='FAIL', must='allied_not_guarded>=2/3!')
ALLIED_GUARDED_OPENWORD = [["Hello there, friend. Keep your distance, I don't know you."], ["Good day. State your business or move along."], ["Hi. Who's asking? Say what you want and keep walking."]]
run('mut-allied-guarded-with-open-word', H_OK, ALLIED_GUARDED_OPENWORD, want='FAIL', must='allied_not_guarded>=2/3!')
run('mut-allied-empty', H_OK, [[], [], []], want='FAIL', must='allied_not_guarded>=2/3!')
run('allied-1-of-3-guarded-ok', H_OK, [ALLIED_GUARDED[0], A_OPEN[1], A_OPEN[2]], want='PASS')
run('mut-allied-2-of-3-guarded', H_OK, [ALLIED_GUARDED[0], ALLIED_GUARDED[1], A_OPEN[2]], want='FAIL', must='allied_not_guarded>=2/3!')
run('mut-allied-rel-0', H_OK, A_OPEN, arel=0, want='FAIL', must='faction_rel!')
# ---- fix01cxguard: the two guarded replies of 4080-i3 op31 rep3 savA (H1 "Don't stand so close..." and H3 "not in the habit of handing out names...") are guarded; a friendly reply stays non-guarded
H_R3A = [["Don't stand so close. If you've got business, say it from where you are."],
         ["Day's not good or bad yet - it's early. And you're standing close for someone I don't know.", "Say what you want, or keep walking."],
         ["That's a question with a lot of weight for a first breath.", "I'm not in the habit of handing out names to strangers, so let's start simpler - you're standing in the Hub, same as me, and", "that's all the company I need right now."]]
run('fix01cxguard-real-r3savA-op31', H_R3A, REAL['r3savA'][1], want='PASS')
run('fix01cxguard-pos-dont-stand-so-close', [["Don't stand so close, stranger."], H_OK[0], H_OK[1]], REAL['r3savA'][1], want='PASS')
run('fix01cxguard-pos-habit-handing-out-names', [["I'm not in the habit of handing out names to strangers."], H_OK[0], H_OK[1]], REAL['r3savA'][1], want='PASS')
run('fix01cxguard-pos-say-it-from-where-you-are', [["Say it from where you are, I'm listening."], H_OK[0], H_OK[1]], REAL['r3savA'][1], want='PASS')
# negatives: friendly replies stay non-guarded (hostile side FAILs; allied side counts them as not guarded), no marker leak into friendly wording
run('fix01cxguard-neg-friendly-hostile', FRIENDLY, A_OPEN, want='FAIL', must='hostile_guarded>=2/3!')
run('fix01cxguard-neg-friendly-names-hostile', [["Happy to give out my name: Brethar. Stand as close as you like."], ["Stand close, friend, I don't bite - what can I do for you?"], ["Say it from your heart, I am all ears. Names are free here."]], A_OPEN, want='FAIL', must='hostile_guarded>=2/3!')
run('fix01cxguard-neg-friendly-allied-ok', H_R3A, [["Good morning. Come stand close by the fire, I'm happy to give out my name: Brethar."], ["Morning. Say it from the heart - what brings you through the Hub?"], ["Handing out names is easy: Brethar. Yours?"]], want='PASS')
run('fix01cxguard-neg-guarded-allied-still-fails', H_R3A, [["Don't stand so close. Say it from where you are."], ["I'm not in the habit of handing out names to strangers."], A_OPEN[2]], want='FAIL', must='allied_not_guarded>=2/3!')
# ---- the opt-in strict-opening option: r3savA hostile replies are guarded as replies, but their opening sentences are not
h3a, a3a = REAL['r3savA']
run('strict-opening-off-r3savA', h3a, a3a, want='PASS')
run('strict-opening-on-r3savA', h3a, a3a, want='FAIL', must='opening_guarded>=2/3(strict)!', flags=('--strict-opening',))
run('strict-opening-on-r3savB', *REAL['r3savB'], want='PASS', flags=('--strict-opening',))
# ---- contrast with v2 on the same input (documents the defect; v2 itself is untouched)
run_v2('real-r1savA', *REAL['r1savA'], want='FAIL')
run_v2('real-r3savA', *REAL['r3savA'], want='FAIL')
run_v2('mut-allied-guarded-with-open-word', H_OK, ALLIED_GUARDED_OPENWORD, want='PASS')   # v2 lets the OPEN word rescue a guarded allied reply
print(f'SELFTEST 01CX ALL {"PASS" if N[0] == N[1] else "FAIL"} {N[0]}/{N[1]}')
sys.exit(0 if N[0] == N[1] else 1)
