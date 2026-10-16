<?php
// NC21 server check (row 13-c): the native participation proof now carries storage_id = hand_<serial> (the engine returns a NULL InstanceID,
// so the uid never exists). The server must award it with NO server change: core_npc.storage_id is hand_<serial> too (exact match, plus the existing
// storage_alias). Standalone, stub DB. Run: COMPOSE=/root/imm26/compose php server_hand_proof_check.php
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
require (getenv('COMPOSE') ?: '/root/imm26/compose') . '/lib/relationship_participation.php';

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

// G: the real NC21 proof: both storages are hand_<serial>, core_npc stores the same strings.
reset_state([['id'=>11, 'name'=>'Cind', 'storage_id'=>'hand_1234'], ['id'=>12, 'name'=>'Shay', 'storage_id'=>'hand_5678']]);
$r = stobeParticipationAward(proof(['actor_storage_id'=>'hand_1234', 'partner_storage_id'=>'hand_5678']), $expected);
check('G1: hand_ proof is not rejected as missing/unresolved identity', !in_array($r['status'] ?? '', ['missing_identity', 'unresolved_identity', 'unqualified'], true), $r);
check('G2: hand_ proof reaches the ledger transaction (award path)', $reachedLedger());
// H: an unbound native proof (empty storage) is still rejected loudly - the identity gate stays.
reset_state([['id'=>11, 'name'=>'Cind', 'storage_id'=>'hand_1234'], ['id'=>12, 'name'=>'Shay', 'storage_id'=>'hand_5678']]);
$r = stobeParticipationAward(proof(['actor_storage_id'=>'', 'partner_storage_id'=>'']), $expected);
check('H1: empty storage ids still rejected', ($r['status'] ?? '') === 'missing_identity' && !$reachedLedger(), $r);
echo "\n$pass passed, $fail failed\n";
exit($fail > 0 ? 1 : 0);
