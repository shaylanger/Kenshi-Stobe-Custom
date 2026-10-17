# Living handoff + auto-compact 150k (Shay 2026-10-16). Run by swap.ps1 (Shay), idempotent, backs up first.
import json, re, shutil, os, sys, time
ws = r'C:\KenshiModding'
bk = r'C:\KenshiTestRuns\backup'
os.makedirs(bk, exist_ok=True)
stamp = time.strftime('%Y%m%d-%H%M%S')

# 1. project .claude/settings.json: autoCompactWindow 183000 (150k + the fixed 33k buffer) + PreCompact + SessionStart(compact) hooks
sp = os.path.join(ws, '.claude', 'settings.json')
shutil.copy2(sp, os.path.join(bk, 'settings.json.pre-livehandoff-' + stamp))
d = json.load(open(sp, encoding='utf-8'))
d['autoCompactWindow'] = 183000
cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File C:/KenshiModding/tools/automation/handoff-snapshot.ps1'
h = d.setdefault('hooks', {})
def add(event, matcher, command):
    arr = h.setdefault(event, [])
    for g in arr:
        for x in g.get('hooks', []):
            if x.get('command') == command:
                return
    g = {'hooks': [{'type': 'command', 'command': command}]}
    if matcher: g['matcher'] = matcher
    arr.append(g)
add('PreCompact', None, cmd)
add('SessionStart', 'compact', cmd + ' -Print')
json.dump(d, open(sp, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)

# 2. project context-meter override: main session warn at 120k (checkpoint the living handoff), NO handoff-session order
mp = os.path.join(ws, '.claude', 'context-meter.project.ps1')
shutil.copy2(mp, os.path.join(bk, 'context-meter.project.ps1.pre-livehandoff-' + stamp))
t = open(mp, encoding='utf-8').read()
new_warn = ('$WARN_MSG = "Context: {tokens} tokens. LIVING-HANDOFF CHECKPOINT (docs/HANDOFF_STANDARD.md): auto-compact runs at about 150k. Now: run the zero-context test '
            '(could a new session continue from testing/COORDINATOR_LIVE.md + HANDOFF Right now + SHAY_DECISIONS.md alone?), update those files, commit + push, then continue normally. '
            'Do not start a new large unit; there is NO handoff session and NO tail any more."')
t2 = re.sub(r'^\$WARN_MSG = "Context: \{tokens\} tokens \(overlap handoff at \{handoff\}\).*$', lambda m: new_warn, t, count=1, flags=re.M)
t2 = t2.replace('$WARN = 270000; $HANDOFF = 300000', '$WARN = 120000; $HANDOFF = 99999999')
if t2 == t:
    print('context-meter.project.ps1: already applied or anchors missing'); 
open(mp, 'w', encoding='utf-8').write(t2)
print('OK settings.json autoCompactWindow=%s hooks=%s' % (d['autoCompactWindow'], [k for k in h]))
