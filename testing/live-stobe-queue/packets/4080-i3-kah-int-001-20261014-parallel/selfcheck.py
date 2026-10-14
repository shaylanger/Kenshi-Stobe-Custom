from pathlib import Path
import hashlib, re, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
BODY = PACKET / 'body.sh'
PINNED = {
    'testing/live-stobe-queue/integrated-AEF84C0A/kah-int-001-chat-hotkey-isolated.sh': '5EA4BD563D0697ECA7B7939F0666F1557D23DCA66598E61EAD24738DE44219F5',
    'testing/live-stobe-queue/4080-i3-command-route.md': 'BAD511F01ADE7726B67F6DCA63F483FA8157CE1996AED99E8FB1D80ABA3B0822',
    'tools/automation/remote-bash-stdin-4080.ps1': '138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354',
    'tools/automation/rig-env.sh': 'A96DF1C3FDD95CF5F96471048F5FC1B63153EA21B6D3AD5A711145F0A80FE20D',
    'tools/automation/rig4080/instance-route-preflight.sh': '408FD0CAC181FEE32EF5DD0D0512CBD10494962CF1E251412EB900AF80E6EF51',
    'tools/automation/loaded-module-probe.ps1': '121956C2A61A4B59854BB12AC414C788A15B9A599D05680D98F78971D705A31F',
    'pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/SOURCE-MANIFEST.json': 'AD63A137D74CFE23DEFF8914B06C56B8DC51693E88FBDA55AE1E365EE7B0445C',
    'pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/PAYLOAD-MANIFEST.json': '475B58A78C02377C3B67B1F7F6677F7E9AD912F018EC737CDE85807AB6D7FB0A',
    'pending-fixes/release-coordination/stobe-native-integrated-candidate-20261013/build-v100/Stobe.dll': 'AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C',
    'pending-fixes/release-staging/stobe-integrated/4080/AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C/Stobe.dll': 'AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C',
}
body = BODY.read_text(encoding='utf-8-sig')
checks = {
    'no trailing whitespace in packet files': all(line.rstrip(' \t') == line for f in (BODY, PACKET/'README.md', Path(__file__)) for line in f.read_text(encoding='utf-8-sig').splitlines()),
    'reviewed wrapper preamble': "export RIG=4080 KAH_INSTANCE=3\nexport KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3\nexport KAH_DIR='C:\\KenshiInst\\3\\mods\\AutomationHarness'\n. /c/KenshiModding/tools/automation/rig-env.sh" in body,
    'all static gates precede first injected key': max(body.index(x) for x in ('rig4080_i3_preflight', 'loaded-module-probe.ps1', 'ChatHotkey_not_exactly_slash', 'current_world_not_expected_unpaused_copied_save', 'natural_focus_or_isolation_changed_before_input')) < body.index('stobe-auto key_inject / tap 120'),
    'scoped tree only and no global ui close': 'stobe-auto ui tree Stobe_ChatWindow up 0' in body and 'stobe-auto ui close' not in body,
    'geometry and unique titlebar close gates': all(x in body for x in ('TREE_FAIL_root_render_client_mismatch', 'TREE_FAIL_close_label_not_unique', 'TREE_FAIL_close_not_inside_titlebar', 'TREE_FAIL_coordinate_outside_client')),
    'no unresolved coordinates or guessed values': '__FRESH_SCREENSHOT_' not in body and 'CANCEL_X=' not in body and 'TEXTBOX_X=' not in body,
    'fresh second chat close verified': 'no visible widget named or captioned' in body and 'second_slash_did_not_close_untouched_chat' in body,
    'only two coordinate click actions (textbox and draft discard)': body.count('stobe-auto mouse_inject left click 80') == 2,
    'no focus/backend/chat-send/save/queue mutation APIs': not any(token.lower() in body.lower() for token in ('AppActivate','SetForegroundWindow','stobe_say','stobe-auto load','stobe-auto save','stobe-auto session','stobe-auto stobe_ping','stobe-auto where','curl ','wget ','php ','18084','input_isolation off')),
}
for rel, want in PINNED.items():
    path=ROOT/rel
    got=hashlib.sha256(path.read_bytes()).hexdigest().upper() if path.is_file() else 'MISSING'
    checks['source pin '+rel]=got==want

m=re.search(r"open_geometry\(\) \{\s*python3 - \"\$1\" \"\$2\" \"\$3\" \"\$\{4:-draft\}\" <<'PY'\n(.*?)\nPY",body,re.S)
if not m:
    checks['extract scoped geometry parser']=False
else:
    parser=m.group(1)
    good='4 widget(s) under Stobe_ChatWindow (up 0) | Stobe_ChatWindow 0,0 800x600 | TitleBar 0,0 800x40 | CloseButton \'Close\' 760,0 30x30 | MessageInput 20,550 760x30'
    cases=[
        ('valid scoped geometry',good,0,'draft'),
        ('ambiguous close rejected',good+' | OtherCancel \'Cancel\' 700,0 30x30',7,'draft'),
        ('out of render bounds rejected',good.replace('760,0 30x30','790,0 30x30'),3,'draft'),
        ('root dimension mismatch rejected',good.replace('0,0 800x600','0,0 799x600'),5,'draft'),
        ('missing titlebar rejected',good.replace(' | TitleBar 0,0 800x40',''),6,'draft'),
        ('close outside titlebar rejected',good.replace('TitleBar 0,0 800x40','TitleBar 0,0 740x40'),8,'draft'),
        ('ambiguous textbox rejected',good+' | MessageEdit2 20,510 760x30',9,'draft'),
        ('untouched open requires only root geometry','1 widget(s) under Stobe_ChatWindow (up 0) | Stobe_ChatWindow 0,0 800x600',0,'open-only'),
    ]
    with tempfile.TemporaryDirectory(prefix='kah-ui-tree-check-') as td:
        for label,tree,expected,mode in cases:
            f=Path(td)/'tree.txt'; f.write_text(tree)
            result=subprocess.run([sys.executable,'-c',parser,str(f),'800','600',mode],capture_output=True,text=True)
            checks[label]=result.returncode==expected
for name,ok in checks.items():
    print(('PASS ' if ok else 'FAIL ')+name)
if not all(checks.values()): sys.exit(1)
print(f'RESULT local-selfcheck PASS checks={len(checks)} remote=0 rig_contact=0 test_input=0')





