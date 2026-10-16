# NC24 source test (row 25-b): NaturalOutput must follow node -> BUILDING_FUNCTIONALITY -> `produces` ITEM refs (iron is two hops away).
# Fails on NC23, passes on NC24. Usage: python3 mine_functionality_produces_source_tests.py <tree>   (checks src/ and legacy-v1/)
import io, os, re, sys
tree = sys.argv[1]; fails = []
for rel in ('src', 'legacy-v1'):
    p = tree + '/' + rel + '/ActivityPolicySupport.cpp'
    s = io.open(p, encoding='utf-8').read() if os.path.exists(p) else ''
    m = re.search(r'InventorySection\* NaturalOutput\(.*?\n\}\n', s, re.S)
    b = m.group(0) if m else ''
    if not b: fails.append(rel + ': NaturalOutput not found'); continue
    if 'BUILDING_FUNCTIONALITY' not in b: fails.append(rel + ': functionality hop missing')
    if '"produces"' not in b: fails.append(rel + ': produces list not read')
    if '>produces' not in b: fails.append(rel + ': how label functionality>produces missing')
    if 'ref->type!=ITEM' not in b or 'prod->type!=ITEM' not in b: fails.append(rel + ': ITEM type filters missing')
    if 'ResolveNaturalProduct(in,resolved,how)' not in b: fails.append(rel + ': ResolveNaturalProduct call changed')
    if 'fn=' not in s: fails.append(rel + ': diag lacks first-hop list names')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
