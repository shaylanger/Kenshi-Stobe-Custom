<?php
// imm26 wp13c (row 13-c): the shared-experience award (lib/relationship_participation.php) must (1) resolve a party whose proof storage id
// is the native InstanceID uid while core_npc stores hand_<serial> (storage_alias), (2) log every outcome with a reason, and (3) keep
// rejecting an EMPTY uid (no hand_ fallback). Standalone: stub DB, no Postgres needed. Fails on the old code.
// Run: php tests/imm26_wp13c_participation_identity_regression.php
declare(strict_types=1);
$pass = 0; $fail = 0;
function check(string $name, bool $ok, $detail = null): void {
    global $pass, $fail;
    if ($ok) { $pass++; echo "PASS $name\n"; } else { $fail++; echo "FAIL $name" . ($detail !== null ? ' :: ' . json_encode($detail) : '') . "\n"; }
}
$LOG = [];
function stobeLogInfo(string $m, array $c = []): void { $GLOBALS['LOG'][] = ['INFO', $m, $c]; }
function stobeLogWarn(string $m, array $c = []): void { $GLOBALS['LOG'][] = ['WARN', $m, $c]; }
function getSetting(string $k, $d = null) { return $d; }
function getSettingBool(string $k, bool $d = false): bool { return $d; }
function getNpcById(int $id): array { return ['id'=>$id]; }
function stobeIsRelationshipSystemEnabled(): bool { return true; }
function normalizeStorageIdToken(mixed $raw): string { return strtolower(trim(strval($raw))); }
function stobeIsGenericNpcName(string $n): bool { return false; }

const CHAR = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const TOK = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final class StubDb {
    public array $sql = [];
    public array $npc = []; // rows: id,name,storage_id
    public function transactionStatus(): int { return defined('PGSQL_TRANSACTION_IDLE') ? PGSQL_TRANSACTION_IDLE : 0; }
    public function fetchOne(string $sql, array $a = []): ?array {
        $this->sql[] = $sql;
        if (str_contains($sql, 'PLAYTHROUGH_SESSION')) return ['value'=>json_encode(['status'=>'ready', 'token'=>TOK, 'character_id'=>CHAR,
            'load_id'=>7, 'client_id'=>'client1', 'auth_mode'=>'current_campaign'])];
        if (str_contains($sql, 'PLAYTHROUGH_CAMPAIGN_ID')) return ['value'=>CHAR];
        return null;
    }
    public function fetchAll(string $sql, array $a = []): array {
        $this->sql[] = $sql;
        if (str_contains($sql, 'FROM core_npc WHERE LOWER(name)')) {
            return array_values(array_filter($this->npc, fn($r) => strtolower($r['name']) === strtolower(strval($a[0]))));
        }
        return [];
    }
    public function exec(string $sql, array $a = []) { $this->sql[] = $sql; return true; } // later pg_fetch_assoc(true) throws -> deferred
}
$db = new StubDb();
$GLOBALS['db'] = $db;
$_SERVER['HTTP_X_STOBE_PLAYTHROUGH'] = TOK;
require __DIR__ . '/../lib/relationship_participation.php';

function proof(array $o = []): array {
    return array_merge(['schema_version'=>1, 'qualified'=>true, 'conscious_alive_all'=>true, 'world_id'=>'w1', 'agreement_id'=>'ag1',
        'task_id'=>'t1', 'mode'=>'travel_accompaniment', 'actor_serial'=>1234, 'partner_serial'=>5678,
        'first_gamets'=>1000, 'last_gamets'=>1060, 'terminal_gamets'=>1061, 'qualified_samples'=>9, 'progress_samples'=>9,
        'actor_distance'=>120, 'partner_distance'=>118, 'max_separation'=>12, 'endpoint_progress'=>110,
        'actor_storage_id'=>'uid-cind-0001', 'actor_name'=>'Cind', 'partner_storage_id'=>'uid-shay-0002', 'partner_name'=>'Shay'], $o);
}
$expected = ['world_id'=>'w1', 'agreement_id'=>'ag1', 'task_id'=>'t1', 'mode'=>'travel_accompaniment', 'actor_serial'=>1234,
    'partner_serial'=>5678, 'game_ts'=>1062, 'evidence_id'=>'ev1'];
$reachedLedger = fn() => count(array_filter($db->sql, fn($q) => str_contains($q, 'FROM social_effect WHERE campaign_id=$1 AND incident_id=$2'))) > 0;
function reset_state(array $npc): void { global $db, $LOG; $db->sql = []; $LOG = []; $db->npc = $npc; }
$lastLog = fn() => end($GLOBALS['LOG']) ?: [null, null, []];

// A: core_npc stores hand_<serial>, proof carries a native uid: resolves through storage_alias and reaches the ledger transaction.
reset_state([['id'=>11, 'name'=>'Cind', 'storage_id'=>'hand_1234'], ['id'=>12, 'name'=>'Shay', 'storage_id'=>'hand_5678']]);
$r = stobeParticipationAward(proof(), $expected);
check('A1: uid vs hand_ storage resolves (not unresolved_identity)', ($r['status'] ?? '') !== 'unresolved_identity', $r);
check('A2: got past identity into the ledger transaction', $reachedLedger());

// B: already-resolvable ids (stored id == proof id) behave as before.
reset_state([['id'=>11, 'name'=>'Cind', 'storage_id'=>'uid-cind-0001'], ['id'=>12, 'name'=>'Shay', 'storage_id'=>'uid-shay-0002']]);
$r = stobeParticipationAward(proof(), $expected);
check('B1: matching storage ids still resolve', ($r['status'] ?? '') !== 'unresolved_identity' && $reachedLedger(), $r);

// C: stored hand_ of a DIFFERENT serial and different uid: still unresolved (alias must not over-match) and it is logged.
reset_state([['id'=>11, 'name'=>'Cind', 'storage_id'=>'hand_9999'], ['id'=>12, 'name'=>'Shay', 'storage_id'=>'hand_5678']]);
$r = stobeParticipationAward(proof(), $expected);
check('C1: other serial stays unresolved', ($r['status'] ?? '') === 'unresolved_identity', $r);
$l = $lastLog();
check('C2: failed award is logged with status+reason', $l[0] === 'WARN' && $l[1] === 'Participation award' && ($l[2]['status'] ?? '') === 'unresolved_identity', $l);
$ids = array_values(array_filter($GLOBALS['LOG'], fn($e) => $e[1] === 'Experience identity unresolved'));
check('C3: identity detail logged (basis per party)', count($ids) === 1 && ($ids[0][2]['observer_basis'] ?? '') === 'none', $ids);

// D: EMPTY uid is rejected, no hand_ fallback, reason names it.
reset_state([['id'=>11, 'name'=>'Cind', 'storage_id'=>'hand_1234'], ['id'=>12, 'name'=>'Shay', 'storage_id'=>'hand_5678']]);
$r = stobeParticipationAward(proof(['actor_storage_id'=>'']), $expected);
$l = $lastLog();
check('D1: empty uid -> missing_identity (no hand_ fallback)', ($r['status'] ?? '') === 'missing_identity' && !$reachedLedger(), $r);
check('D2: reason empty_instance_uid_actor logged', ($l[2]['reason'] ?? '') === 'empty_instance_uid_actor', $l);

// E: participation proof reasons.
$cases = [
    'too_few_samples' => ['qualified_samples'=>2],
    'too_short' => ['last_gamets'=>1010, 'terminal_gamets'=>1011],
    'separation' => ['max_separation'=>40],
];
foreach ($cases as $reason => $o) {
    reset_state([]);
    $r = stobeParticipationAward(proof($o), $expected);
    $l = $lastLog();
    check("E: $reason", ($r['status'] ?? '') === 'insufficient_participation' && ($l[2]['reason'] ?? '') === $reason, [$r, $l]);
}
reset_state([]);
$r = stobeParticipationAward(proof(['qualified'=>false]), $expected);
check('E: unqualified proof logged', ($r['status'] ?? '') === 'unqualified' && ($lastLog()[2]['reason'] ?? '') === 'participation_proof_missing_or_unqualified');
reset_state([]);
$r = stobeParticipationAward(proof(['actor_distance'=>5]), $expected);
check('E: walked too little logged', ($r['status'] ?? '') === 'insufficient_progress' && ($lastLog()[2]['reason'] ?? '') === 'walked_too_little');

// F: native proof thresholds unchanged (exactly 4 samples, exactly 30 s, exactly 35 u separation still pass the server gate).
reset_state([['id'=>11, 'name'=>'Cind', 'storage_id'=>'hand_1234'], ['id'=>12, 'name'=>'Shay', 'storage_id'=>'hand_5678']]);
$r = stobeParticipationAward(proof(['qualified_samples'=>4, 'last_gamets'=>1030, 'terminal_gamets'=>1031, 'max_separation'=>35]), $expected);
check('F1: boundary proof (4 samples, 30 s, 35 u) still accepted by the gate', !in_array($r['status'] ?? '', ['insufficient_participation', 'unqualified'], true), $r);

echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
