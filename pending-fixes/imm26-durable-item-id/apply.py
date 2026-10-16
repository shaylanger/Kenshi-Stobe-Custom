#!/usr/bin/env python3
"""imm26-durable-item-id (Shay approved 'size 3', 2026-10-15): restitution after a save/load.

Problem: the theft receipt's item_key is the load-local native item handle ("hand_<serial>") and entities are
session:epoch:serial. repairReturnedProperty therefore refused any return whose epoch/session differs from the theft's, so an
item returned AFTER a reload could never become a verified credited repair (wpR2 documented this and kept exactness).
No save-persistent native item id is known (SR34: serials are reused after reload/import), so this is the SERVER-ONLY option:
a cross-load FINGERPRINT match, deliberately strict. A returned item is attributed to the original stolen item only when ALL hold
  - setting STOBE_REPAIR_FINGERPRINT_ENABLED (default on; env STOBE_REPAIR_FINGERPRINT_ENABLED=0 also disables) and the existing
    stobeSocialRepairScopeCurrent() rescope guard (same campaign, newer numeric epoch, non-empty session, giver/recipient storage ids);
  - the return event carries native-verified whole-stack proof (checked by the unchanged code), from the thief to the owner;
  - same prototype_id, same type_key, EQUAL quantity (a whole stack), original direction owner->thief;
  - exactly ONE original stolen item and exactly ONE returned item share that fingerprint (any duplicate -> not credited);
  - exactly one theft incident matches overall (unchanged count($matches)!==1 rule) and the theft is not later than the return.
The returned move is rewritten to the original item_key, so every downstream check (quantity caps, per-item verified_items,
agreement tickets/allocations) works unchanged; the load-local key is kept as verified_items[...].return_item_key.
Same-load behaviour is unchanged. Residual risk (documented): a thief giving a DIFFERENT own stack of the same type and
quantity is indistinguishable server-side; credit stays capped by the owed quantity of that type.
Usage (WSL): python3 apply.py <tree-root>   (idempotent; anchored; CRLF-aware; installs the regression test)"""
import sys, os
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
TEST = 'imm26_durable_item_id_regression.php'


def rd(p):
    raw = open(p, 'rb').read().decode('utf-8')
    return ('\r\n' in raw), raw.replace('\r\n', '\n')


def wr(p, s, crlf):
    open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode('utf-8'))


ps = os.path.join(root, 'lib', 'social_repair_store.php')
pa = os.path.join(root, 'lib', 'social_repair_agreements.php')
crlf_s, s = rd(ps)
crlf_a, a = rd(pa)
if 'stobeSocialRepairFingerprintKeyMap' in s and 'stobeSocialRepairFingerprintKeyMap' in a:
    print('already applied')
    sys.exit(0)

S1 = "            $this->lock($event['campaign_id']);\n            $matches=[];\n            foreach ($candidates as [$r,$s]) {\n"
S1n = "            $this->lock($event['campaign_id']);\n            require_once __DIR__ . '/social_repair_agreements.php';\n            $matches=[];\n            foreach ($candidates as [$r,$s]) {\n"
S2 = ("                if (($original['verified'] ?? false)!==true || ($original['method'] ?? '')!=='same_live_item_whole_stack'\n"
      "                    || ($s['native_session_id'] ?? '')!==$event['native_session_id'] || $r['timeline_epoch']!==$event['timeline_epoch']) continue;\n"
      "                $moves=[];\n")
S2n = ("                if (($original['verified'] ?? false)!==true || ($original['method'] ?? '')!=='same_live_item_whole_stack') continue;\n"
       "                $sameLoad=($s['native_session_id'] ?? '')===$event['native_session_id'] && $r['timeline_epoch']===$event['timeline_epoch'];\n"
       "                // imm26 durable-item-id: a later load may match by strict fingerprint (see stobeSocialRepairFingerprintKeyMap).\n"
       "                $keyMap=$sameLoad ? [] : stobeSocialRepairFingerprintKeyMap($event,$r,$s,$proof['items'] ?? [],$original['items'] ?? [],$giverStorage,$receiverStorage);\n"
       "                if (!$sameLoad && !$keyMap) continue;\n"
       "                $moves=[];\n")
S3 = ("                    if (!is_array($move) || ($move['from_storage_id'] ?? '')!==$giverStorage || ($move['to_storage_id'] ?? '')!==$receiverStorage\n"
      "                        || !is_int($move['quantity'] ?? null) || $move['quantity']<=0) continue;\n")
S3n = S3 + ("                    if (!$sameLoad) {\n"
            "                        $loadKey=strval($move['item_key'] ?? '');\n"
            "                        if (!isset($keyMap[$loadKey])) continue;\n"
            "                        $move['return_item_key']=$loadKey;$move['item_key']=$keyMap[$loadKey];\n"
            "                    }\n")
S4 = "$repair['verified_items'][$itemKey]=['event_id'=>$event['event_id'],'quantity'=>$itemReturned+$qty,'prototype_id'=>$move['prototype_id']];"
S4n = ("$repair['verified_items'][$itemKey]=['event_id'=>$event['event_id'],'quantity'=>$itemReturned+$qty,'prototype_id'=>$move['prototype_id']]\n"
       "                    +(isset($move['return_item_key']) ? ['return_item_key'=>$move['return_item_key'],'matched_by'=>'cross_load_fingerprint'] : []);")
S5 = "$agreementTicket=stobeSocialRepairAgreementTicketForEvent($event);"
S5n = ("$ticketEvent=$event;$toOriginal=[];\n"
       "            foreach ($moves as $m) if (isset($m['return_item_key'])) $toOriginal[$m['return_item_key']]=$m['item_key'];\n"
       "            if ($toOriginal) foreach ($ticketEvent['facts']['transfer_evidence']['items'] as &$ti) if (isset($toOriginal[$ti['item_key'] ?? ''])) $ti['item_key']=$toOriginal[$ti['item_key']];\n"
       "            unset($ti);\n"
       "            $agreementTicket=stobeSocialRepairAgreementTicketForEvent($ticketEvent);")
for x in (S1, S2, S3, S4, S5):
    assert s.count(x) == 1, 'anchor missing in store: ' + x[:70]
for x, y in ((S1, S1n), (S2, S2n), (S3, S3n), (S4, S4n), (S5, S5n)):
    s = s.replace(x, y)

HELP = r'''
function stobeSocialRepairFingerprintEnabled(): bool {
    $v = getenv('STOBE_REPAIR_FINGERPRINT_ENABLED');
    if ($v !== false && $v !== '') return !in_array(strtolower(trim($v)), ['0','false','no','off'], true);
    try { return getSettingBool('STOBE_REPAIR_FINGERPRINT_ENABLED', true); } catch (Throwable $e) { return true; }
}

/**
 * imm26 durable-item-id. Cross-load only (the caller handles same-load by exact item_key). Maps load-local returned item key =>
 * original stolen item key for strictly unambiguous whole-stack fingerprint matches, otherwise returns [] (fail closed).
 * Fingerprint = prototype_id + type_key + quantity + direction (owner->thief originally, thief->owner on return).
 * Any duplicate of a fingerprint among the original items OR among the returned items makes that fingerprint unusable.
 */
function stobeSocialRepairFingerprintKeyMap(array $event,array $row,array $theft,array $returned,array $original,string $giver,string $receiver): array {
    if (!stobeSocialRepairFingerprintEnabled() || $giver==='' || $receiver==='' || $giver===$receiver) return [];
    $scope=['campaign_id'=>$event['campaign_id'] ?? null,'timeline_epoch'=>strval($row['timeline_epoch'] ?? ''),
        'native_session_id'=>strval($theft['native_session_id'] ?? ''),'giver_storage_id'=>$giver,'recipient_storage_id'=>$receiver];
    if ($scope['native_session_id']==='' || !stobeSocialRepairScopeCurrent($scope,['campaign_id'=>$event['campaign_id'] ?? null,
        'timeline_epoch'=>strval($event['timeline_epoch'] ?? ''),'native_session_id'=>strval($event['native_session_id'] ?? '')])) return [];
    $fp=static function(array $i,string $from,string $to):?string {
        $key=$i['item_key'] ?? null;$q=$i['quantity'] ?? null;
        if (!is_string($key) || $key==='' || !is_int($q) || $q<=0) return null;
        foreach (['prototype_id','type_key'] as $f) if (!is_string($i[$f] ?? null) || $i[$f]==='') return null;
        if (($i['from_storage_id'] ?? null)!==$from || ($i['to_storage_id'] ?? null)!==$to) return null;
        return json_encode([$i['prototype_id'],$i['type_key'],$q]);
    };
    $orig=[];$ret=[];
    foreach ($original as $i) { if (!is_array($i)) return []; $f=$fp($i,$receiver,$giver); if ($f===null) return []; $orig[$f][]=$i['item_key']; }
    foreach ($returned as $i) { if (!is_array($i)) return []; $f=$fp($i,$giver,$receiver); if ($f===null) return []; $ret[$f][]=$i['item_key']; }
    $map=[];
    foreach ($ret as $f=>$keys) if (count($keys)===1 && isset($orig[$f]) && count($orig[$f])===1) $map[$keys[0]]=$orig[$f][0];
    return $map;
}
'''
a = a.rstrip('\n') + '\n' + HELP
wr(ps, s, crlf_s)
wr(pa, a, crlf_a)
t = open(os.path.join(here, TEST), 'rb').read().decode('utf-8').replace('\r\n', '\n')
wr(os.path.join(root, 'tests', TEST), t, crlf_s)
print('applied')
