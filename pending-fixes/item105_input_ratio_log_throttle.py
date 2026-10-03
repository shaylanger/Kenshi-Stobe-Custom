#!/usr/bin/env python3
"""Item 105 (m16 A8): `WORK_GOAL input ratio ...` was logged on every planner pass (~15/s): 30,146 lines in one
A8 run, burying the useful KenshiFP.log lines. Log each (machine, input, result) once per 30 s instead (8-slot memory: one pass logs oven, silo and farm).
Usage: item105_input_ratio_log_throttle.py <KenshiFP root>"""
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]) / 'client' / 'stobe_work_planner.inc'
s = p.read_text(encoding='utf-8', errors='surrogateescape')
if 'Item 105' in s: sys.exit('already applied')
m = re.search(r'\n(\s*)logline\("\[stobe\] WORK_GOAL input ratio %s: %s x%\.2f \(in %\.3f / out %\.3f\) -> %d for %d",\n(.*?\);)', s, re.S)
if not m: sys.exit('anchor missing')
indent = m.group(1)
old = m.group(0)
call = old.strip('\n')
new = ('\n' + indent + '{ /* Item 105: once per (machine, input, result) per 30 s, not every pass */\n'
       + indent + '    static unsigned s_ratio_key; static DWORD s_ratio_ms;\n'
       + indent + '    unsigned k=(unsigned)(uintptr_t)prod ^ ((unsigned)(uintptr_t)dep_gd<<1) ^ ((unsigned)need<<7) ^ (unsigned)outputs;\n'
       + indent + '    if (k!=s_ratio_key || (LONG)(GetTickCount()-s_ratio_ms)>30000) { s_ratio_key=k; s_ratio_ms=GetTickCount();\n'
       + '    ' + call + '\n'
       + indent + '    }\n' + indent + '}')
s = s.replace(old, new, 1)
# one planner pass logs several machines: keep an 8-slot memory of keys instead of the last one
s = s.replace('static unsigned s_ratio_key; static DWORD s_ratio_ms;',
              'static unsigned s_ratio_key[8]; static DWORD s_ratio_ms[8]; static int s_ratio_next; int slot=-1;')
s = s.replace('if (k!=s_ratio_key || (LONG)(GetTickCount()-s_ratio_ms)>30000) { s_ratio_key=k; s_ratio_ms=GetTickCount();',
              'for (int q=0;q<8;q++) if (s_ratio_key[q]==k) slot=q;
' + indent + '    if (slot<0 || (LONG)(GetTickCount()-s_ratio_ms[slot])>30000) { if (slot<0) { slot=s_ratio_next; s_ratio_next=(s_ratio_next+1)%8; } s_ratio_key[slot]=k; s_ratio_ms[slot]=GetTickCount();')
p.write_text(s, encoding='utf-8', errors='surrogateescape'); print('patched', p)
