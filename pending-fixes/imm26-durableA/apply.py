#!/usr/bin/env python3
"""imm26 10-f OPTION A (Shay 2026-10-16): credit a cross-load return by the NATIVE durable item id.
The native NC26 build stamps sdata['StobeDurableItemId'] (sdi1-<16 hex>) on an item at exact-transfer evidence time; the engine saves it
with the item (like Profession Gear's persistent id) and restores it after a reload, so the theft row and the later return row
carry the SAME 'durable_item_id' although hand_<serial> changed. Server side (this patch, ON TOP OF option B, which stays the fallback):
  - social_event_contract.php: a transfer item's durable_item_id must be 'sdi1-' + 16 lowercase hex (else the event is rejected like other bad fields).
  - social_repair_agreements.php stobeSocialRepairFingerprintKeyMap (B): FIRST match returned->original by durable id: id appears exactly once
    among the original items and once among the returned items, same prototype_id + type_key, returned quantity <= original quantity,
    direction thief->owner (the unchanged per-item fingerprint() direction checks). Identity is exact, so a smaller whole stack (thief ate some) is fine;
    the store's stolen_quantity / owed-quantity caps still apply.
  - THEN the unchanged B fingerprint fallback, only among items NOT consumed by an id match, and only for returned items WITHOUT a durable id
    (a returned item carrying an id that matches no original is a known different object: never fingerprinted).
  - Setting STOBE_REPAIR_DURABLE_ID_ENABLED (default on; env override, same style as STOBE_REPAIR_FINGERPRINT_ENABLED). All existing scope guards stay.
Usage (WSL): python3 apply.py <tree-root> [--with-b]   (--with-b first runs ../imm26-durable-item-id/apply.py when B is missing; idempotent; CRLF-aware;
installs tests/imm26_durable_item_id_native_regression.php)"""
import sys, os, subprocess
args = [a for a in sys.argv[1:] if not a.startswith('--')]
root = args[0]
here = os.path.dirname(os.path.abspath(__file__))
TEST = 'imm26_durable_item_id_native_regression.php'

def rd(p):
    raw = open(p, 'rb').read().decode('utf-8')
    return ('\r\n' in raw), raw.replace('\r\n', '\n')
def wr(p, s, crlf):
    open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode('utf-8'))

pa = os.path.join(root, 'lib', 'social_repair_agreements.php')
pc = os.path.join(root, 'lib', 'social_event_contract.php')
crlf_a, a = rd(pa)
if 'stobeSocialRepairFingerprintKeyMap' not in a:
    if '--with-b' not in sys.argv:
        sys.exit('option B (pending-fixes/imm26-durable-item-id) is not applied; rerun with --with-b')
    subprocess.check_call([sys.executable, os.path.join(here, '..', 'imm26-durable-item-id', 'apply.py'), root])
    crlf_a, a = rd(pa)
crlf_c, c = rd(pc)
if 'stobeSocialRepairDurableIdEnabled' in a and 'Invalid durable item id' in c:
    print('already applied'); sys.exit(0)
assert 'stobeSocialRepairDurableIdEnabled' not in a and 'Invalid durable item id' not in c, 'half applied'

C1 = "                    $seen[$key]=true;$type=$item['type_key'];"
C1n = ("                    if (isset($item['durable_item_id']) && (!is_string($item['durable_item_id']) || !preg_match('/^sdi1-[0-9a-f]{16}$/D',$item['durable_item_id'])))\n"
       "                        throw new DomainException('Invalid durable item id');\n" + C1)
assert c.count(C1) == 1, 'contract anchor'
c = c.replace(C1, C1n)

OLD_HEAD = "    if (!stobeSocialRepairFingerprintEnabled() || $giver==='' || $receiver==='' || $giver===$receiver) return [];\n"
NEW_HEAD = ("    $fpOn=stobeSocialRepairFingerprintEnabled();$idOn=stobeSocialRepairDurableIdEnabled();\n"
            "    if ((!$fpOn && !$idOn) || $giver==='' || $receiver==='' || $giver===$receiver) return [];\n")
OLD_TAIL = ("    $orig=[];$ret=[];\n"
"    foreach ($original as $i) { if (!is_array($i)) return []; $f=$fp($i,$receiver,$giver); if ($f===null) return []; $orig[$f][]=$i['item_key']; }\n"
"    foreach ($returned as $i) { if (!is_array($i)) return []; $f=$fp($i,$giver,$receiver); if ($f===null) return []; $ret[$f][]=$i['item_key']; }\n"
"    $map=[];\n"
"    foreach ($ret as $f=>$keys) if (count($keys)===1 && isset($orig[$f]) && count($orig[$f])===1) $map[$keys[0]]=$orig[$f][0];\n"
"    return $map;\n}\n")
NEW_TAIL = r'''    // imm26 10-f A: native save-persistent id (sdi1-<16 hex>, written into the item's save data by the NC26 DLL).
    $idOf=static function(array $i):?string { $d=$i['durable_item_id'] ?? null; return is_string($d) && preg_match('/^sdi1-[0-9a-f]{16}$/D',$d) ? $d : null; };
    $origItems=[];$retItems=[];$origId=[];$retId=[];
    foreach ($original as $i) { if (!is_array($i) || $fp($i,$receiver,$giver)===null) return []; $origItems[]=$i; if (($d=$idOf($i))!==null) $origId[$d][]=$i; }
    foreach ($returned as $i) { if (!is_array($i) || $fp($i,$giver,$receiver)===null) return []; $retItems[]=$i; if (($d=$idOf($i))!==null) $retId[$d][]=$i; }
    $map=[];$usedOrig=[];$usedRet=[];
    if ($idOn) foreach ($retId as $d=>$rs) {
        if (count($rs)!==1 || !isset($origId[$d]) || count($origId[$d])!==1) continue;
        $o=$origId[$d][0];$x=$rs[0];
        if ($o['prototype_id']!==$x['prototype_id'] || $o['type_key']!==$x['type_key'] || $x['quantity']>$o['quantity']) continue;
        $map[$x['item_key']]=$o['item_key'];$usedOrig[$o['item_key']]=true;$usedRet[$x['item_key']]=true;
    }
    // Fallback (option B): type fingerprint among the items the id match did not consume; a returned item that carries an id is never fingerprinted.
    $orig=[];$ret=[];
    if ($fpOn) {
        foreach ($origItems as $i) if (!isset($usedOrig[$i['item_key']])) $orig[$fp($i,$receiver,$giver)][]=$i['item_key'];
        foreach ($retItems as $i) if (!isset($usedRet[$i['item_key']]) && $idOf($i)===null) $ret[$fp($i,$giver,$receiver)][]=$i['item_key'];
        foreach ($ret as $f=>$keys) if (count($keys)===1 && isset($orig[$f]) && count($orig[$f])===1) $map[$keys[0]]=$orig[$f][0];
    }
    return $map;
}

function stobeSocialRepairDurableIdEnabled(): bool {
    $v = getenv('STOBE_REPAIR_DURABLE_ID_ENABLED');
    if ($v !== false && $v !== '') return !in_array(strtolower(trim($v)), ['0','false','no','off'], true);
    try { return getSettingBool('STOBE_REPAIR_DURABLE_ID_ENABLED', true); } catch (Throwable $e) { return true; }
}
'''
assert a.count(OLD_HEAD) == 1 and a.count(OLD_TAIL) == 1, 'agreements anchors (is option B applied unmodified?)'
a = a.replace(OLD_HEAD, NEW_HEAD).replace(OLD_TAIL, NEW_TAIL)
wr(pa, a, crlf_a); wr(pc, c, crlf_c)
t = open(os.path.join(here, TEST), 'rb').read().decode('utf-8').replace('\r\n', '\n')
wr(os.path.join(root, 'tests', TEST), t, crlf_a)
print('applied')
