#!/usr/bin/env python3
"""kfp-probe-schema.py <KenshiFP root>: the fp_combat_probe telemetry carries a schema version (B06 "versioned schema",
COMBAT_TEST_PLAN Gate 0; b-stubs 2026-10-11).

Why: B06 requires measured state, bounded events, overflow reporting AND a versioned schema. The first three are covered by
test_combat_probe.c (B07); the probe replies (begin / state / events page header) had no version, so a reader could not
tell a changed CSV event layout from a valid capture. Fix: KFP_COMBAT_PROBE_SCHEMA (1 = the 13-field CSV event row
seq,ms,frame,kind,actor,ranged,gun,target,state,mode,ammo,stat,dt) is printed as schema=<n> in all three replies; the
decoder (tests/capture_native_ranged.py parse_page) refuses a page with no or another schema; test_combat_probe.c and
test_native_trace.py assert both. Additive token: existing key=value readers (fp-manual-soak.sh, kahstub) are unaffected.
Patches client/kfp_combat_probe.inc + tests. Asserts its anchors; idempotent."""
import sys, os
root = sys.argv[1]
if os.path.exists(os.path.join(root, 'kenshifp_client.c')):
    root = os.path.dirname(os.path.abspath(root))
TAG = 'KFP_COMBAT_PROBE_SCHEMA'

def patch(rel, pairs, tag=TAG):
    p = os.path.join(root, rel)
    if not os.path.exists(p):
        print('kfp-probe-schema: %s absent, skipped' % rel); return
    s = open(p).read()
    if tag in s:
        print('kfp-probe-schema: %s already applied' % rel); return
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, 'kfp-probe-schema: anchor count %d in %s: %r' % (n, rel, old[:80])
        s = s.replace(old, new)
    open(p, 'w').write(s)
    print('kfp-probe-schema: patched %s' % rel)

patch('client/kfp_combat_probe.inc', [
    ('static uint64_t g_combat_probe_capture;\n',
     'static uint64_t g_combat_probe_capture;\n'
     '#define KFP_COMBAT_PROBE_SCHEMA 1   /* B06: bump when the event CSV row / reply keys change (decoder checks it) */\n'),
    ('snprintf(b,sizeof(b),"recording=1 manual_dispatch=0 capture=%llu",(unsigned long long)g_combat_probe_capture);',
     'snprintf(b,sizeof(b),"recording=1 manual_dispatch=0 capture=%llu schema=%d",(unsigned long long)g_combat_probe_capture,KFP_COMBAT_PROBE_SCHEMA);'),
    ('snprintf(b,sizeof(b),"capture=%llu next=%llu oldest=%llu lost=%llu count=%u\\n",\n'
     '                 (unsigned long long)g_combat_probe_capture,',
     'snprintf(b,sizeof(b),"schema=%d capture=%llu next=%llu oldest=%llu lost=%llu count=%u\\n",\n'
     '                 KFP_COMBAT_PROBE_SCHEMA,(unsigned long long)g_combat_probe_capture,'),
    ('"recording=%d frame=%llu next=%llu count=%u manual_dispatch=0 actor_observed=%d capture=%llu",',
     '"recording=%d frame=%llu next=%llu count=%u manual_dispatch=0 actor_observed=%d capture=%llu schema=%d",'),
    ('(unsigned long long)g_combat_probe_capture);\n    r->append(r,b); return KAH_OK;',
     '(unsigned long long)g_combat_probe_capture,KFP_COMBAT_PROBE_SCHEMA);\n    r->append(r,b); return KAH_OK;'),
])
patch('tests/test_combat_probe.c', [
    ('    assert(strstr(output,"recording=0"));\n',
     '    assert(strstr(output,"recording=0"));\n'
     '    assert(strstr(output,"schema=1")); /* B06 KFP_COMBAT_PROBE_SCHEMA versioned replies */\n'),
    ('    assert(command("events","4")==KAH_OK); assert(strstr(output,"through=4 more=0"));\n',
     '    assert(command("events","4")==KAH_OK); assert(strstr(output,"through=4 more=0"));\n'
     '    assert(!strncmp(output,"schema=1 capture=",17));\n'),
])
patch('tests/capture_native_ranged.py', [
    ('FIELDS = "seq ms frame kind actor ranged gun target state mode ammo stat dt".split()\n',
     'FIELDS = "seq ms frame kind actor ranged gun target state mode ammo stat dt".split()\n'
     'KFP_COMBAT_PROBE_SCHEMA = 1   # B06: client/kfp_combat_probe.inc version of FIELDS + page keys\n'),
    ('def parse_page(detail, capture, after):\n',
     'def parse_page(detail, capture, after):\n'
     '    schema = re.findall(r"\\bschema=(\\d+)", detail)\n'
     '    if schema != [str(KFP_COMBAT_PROBE_SCHEMA)]:\n'
     '        raise ValueError("unversioned or unknown probe schema %r" % schema)\n'),
])
patch('tests/test_native_trace.py', [
    ('    def test_flattened_reply(self):\n        row=event(1)\n        header="capture=7 next=2 oldest=1 lost=0 count=1 "\n',
     '    def test_schema_version_required(self):  # B06 KFP_COMBAT_PROBE_SCHEMA\n'
     '        page=" capture=7 next=2 oldest=1 lost=0 count=1 "+token(event(1))+" through=1 more=0"\n'
     '        for bad in ("","schema=2","schema=1 schema=1"):\n'
     '            with self.assertRaises(ValueError): parse_page(bad+page,7,0)\n'
     '        self.assertEqual(parse_page("schema=1"+page,7,0)[0]["through"],1)\n'
     '    def test_flattened_reply(self):\n        row=event(1)\n        header="schema=1 capture=7 next=2 oldest=1 lost=0 count=1 "\n'),
    ('                parse_page(f"capture={capture} next=2',
     '                parse_page(f"schema=1 capture={capture} next=2'),
    ('    def test_truncation_gap_bounds_and_footer_fail(self):\n        header="capture=7 ',
     '    def test_truncation_gap_bounds_and_footer_fail(self):\n        header="schema=1 capture=7 '),
], tag='test_schema_version_required')
