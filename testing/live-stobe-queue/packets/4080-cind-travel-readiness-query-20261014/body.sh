export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail

# Read-only, actor-scoped private-i3 DB fact capture. Operator-owned execution only.

rig4080_i3_preflight >/dev/null 2>&1 || { echo 'RESULT 4080-CIND-TRAVEL-READINESS FAIL setup=private_i3_route_gate'; exit 2; }

php_source=$(cat <<'KAH_PHP'
<?php
error_reporting(0);
set_error_handler(static function () { return true; });
$out = ['query_status'=>'FAIL', 'mechanical_gate'=>'INCOMPLETE', 'database'=>'', 'actor'=>'Cind [Hungry Bandit]', 'serial'=>2529907200,
        'affinity'=>null, 'affinity_source'=>null, 'positive_affinity'=>null, 'candidates'=>[], 'observed_unix'=>time()];
$parseShayAffinity = static function (string $raw): ?int {
    $decoded = json_decode($raw, true);
    if (is_string($decoded)) {
        $raw = $decoded;
        $decoded = json_decode($raw, true);
    }
    if (is_array($decoded)) {
        $listRows = array_is_list($decoded);
        foreach ($decoded as $name => $entry) {
            if (is_array($entry)) {
                // Match stobeNormalizeRelationshipMap(): list rows use target/name;
                // associative maps bind the value to the outer key. Missing affinity defaults to zero.
                $target = trim((string)($listRows ? ($entry['target'] ?? ($entry['name'] ?? '')) : $name));
                if (strcasecmp($target, 'Shay') !== 0) continue;
                $value = $entry['aff'] ?? ($entry['affinity'] ?? 0);
                return max(-100, min(100, (int)$value));
            }
            if ($listRows) continue;
            if (strcasecmp(trim((string)$name), 'Shay') !== 0) continue;
            // Scalar affinity entries are also accepted by the normalizer.
            return max(-100, min(100, is_numeric($entry) ? (int)$entry : 0));
        }
        return null;
    }
    $found = null;
    foreach (preg_split('/\r\n|\r|\n/', trim($raw)) ?: [] as $line) {
        $line = ltrim(trim($line), " \t-*");
        if ($line === '') continue;
        $name = ''; $value = null; $m = [];
        if (preg_match('/^(.+?)\s*:\s*[A-Za-z][A-Za-z ]{0,31}\s*\(\s*[A-Za-z][A-Za-z0-9_-]{0,31}\s*,\s*aff\s*([+-]?[0-9]{1,3})\s*\)(?:\s*\|\s*.*)?$/', $line, $m) === 1) {
            $name = trim($m[1]); $value = (int)$m[2];
        } elseif (preg_match('/^(.+?)\s*-\s*([+-]?[0-9]{1,3})\s*\(\s*[A-Za-z][A-Za-z ]{0,31}\s*,\s*[A-Za-z][A-Za-z0-9_-]{0,31}\s*\)(?:\s*\|\s*.*)?$/', $line, $m) === 1) {
            $name = trim($m[1]); $value = (int)$m[2];
        } elseif (preg_match('/^(.+?)\s*:\s*([+-]?[0-9]{1,3})\s*$/', $line, $m) === 1) {
            $name = trim($m[1]); $value = (int)$m[2];
        }
        if (strcasecmp($name, 'Shay') === 0 && $value !== null) $found = max(-100, min(100, $value));
    }
    return $found;
};
$stage = 'profile';
try {
    $host = getenv('STOBE_DB_HOST'); $port = getenv('STOBE_DB_PORT');
    $name = getenv('STOBE_DB_NAME'); $user = getenv('STOBE_DB_USER');
    $password = getenv('STOBE_DB_PASSWORD');
    if ($password === false) $password = '';
    if ($host !== '/tmp/stobe-standalone4080/socket' || $port !== '15434'
        || $name !== 'stobe_standalone4080_test' || $user !== 'dwemer'
        || !is_string($password) || strlen($password) > 2048 || str_contains($password, "\0")) throw new RuntimeException('profile');
    // Pass the opaque password through libpq's environment channel; never
    // interpolate it into conninfo where spaces could add/override parameters.
    putenv('PGPASSWORD='.$password);
    $parts = ['host='.$host, 'port='.$port, 'dbname='.$name, 'user='.$user, 'connect_timeout=4'];
    $stage = 'connect';
    $db = @pg_connect(implode(' ', $parts), PGSQL_CONNECT_FORCE_NEW);
    if (!$db) throw new RuntimeException('connect');
    @pg_query($db, 'BEGIN READ ONLY');
    $stage = 'identity';
    $identity = @pg_query($db, "SELECT current_database(), current_user, coalesce(inet_server_addr()::text,'socket'), current_setting('listen_addresses'), current_setting('port')");
    $ident = $identity ? pg_fetch_row($identity) : false;
    if (!is_array($ident) || $ident[0] !== 'stobe_standalone4080_test' || $ident[1] !== 'dwemer'
        || $ident[2] !== 'socket' || trim($ident[3]) !== '' || $ident[4] !== '15434') throw new RuntimeException('identity');
    $out['database'] = $ident[0];
    $stage = 'actor_query';
    $sql = "SELECT c.metadata->'travel_destinations' AS destinations, c.relationships AS legacy_relationships,
                   (c.extended_data->'relationships')::text AS extended_relationships
            FROM core_npc c WHERE c.metadata->>'storage_id'='hand_2529907200' LIMIT 2";
    $res = @pg_query_params($db, $sql, []);
    if (!$res) throw new RuntimeException('actor_query');
    if (pg_num_rows($res) !== 1) throw new RuntimeException('actor_scope_missing_or_ambiguous');
    $row = pg_fetch_assoc($res);
    $extendedAffinity = $parseShayAffinity((string)($row['extended_relationships'] ?? ''));
    if ($extendedAffinity !== null) {
        $out['affinity'] = $extendedAffinity;
        $out['affinity_source'] = 'extended_data';
    } else {
        $out['affinity'] = $parseShayAffinity((string)($row['legacy_relationships'] ?? ''));
        if ($out['affinity'] !== null) $out['affinity_source'] = 'relationships_column';
        else { $out['affinity'] = 0; $out['affinity_source'] = 'runtime_default'; }
    }
    $out['positive_affinity'] = ($out['affinity'] >= 0);
    $dest = json_decode((string)($row['destinations'] ?? '[]'), true);
    if (is_array($dest)) foreach (array_slice($dest, 0, 32) as $d) {
        if (!is_array($d) || (int)($d['actor_serial'] ?? 0) !== 2529907200) continue;
        $id = (string)($d['id'] ?? ''); $label = trim((string)($d['label'] ?? ''));
        if (!preg_match('/\A[A-Za-z0-9_.:-]{1,96}\z/D', $id) || $label === '' || strlen($label) > 120
            || preg_match('/[@|;\r\n]/', $label)) continue;
        $point = [];
        foreach (['x','y','z'] as $axis) {
            if (!is_numeric($d[$axis] ?? null) || !is_finite((float)$d[$axis]) || abs((float)$d[$axis]) > 10000000) continue 2;
            $point[$axis] = (float)$d[$axis];
        }
        $observed = is_numeric($d['observed_unix'] ?? null) ? (int)$d['observed_unix'] : 0;
        $age = $observed > 0 ? $out['observed_unix'] - $observed : null;
        $hubMatch = strcasecmp($label, 'The Hub') === 0 && abs($point['x'] - (-50978.8)) <= 1.0
            && abs($point['y'] - 1533.1) <= 1.0 && abs($point['z'] - 2932.5) <= 1.0;
        $out['candidates'][] = ['id'=>$id, 'label'=>$label, 'x'=>$point['x'], 'y'=>$point['y'], 'z'=>$point['z'],
            'target_endpoint_match'=>$hubMatch,
            'actor_serial'=>2529907200, 'observed'=>($d['observed'] ?? null) === true,
            'reachability'=>(string)($d['reachability'] ?? ''), 'observed_unix'=>$observed,
            'age_seconds'=>$age, 'fresh_300s'=>($age !== null && $age >= -30 && $age <= 300)];
    }
    @pg_query($db, 'COMMIT');
    $out['query_status'] = 'OK';
    foreach ($out['candidates'] as $candidate) {
        if ($candidate['target_endpoint_match'] === true && $candidate['actor_serial'] === 2529907200
            && $candidate['observed'] === true && $candidate['reachability'] === 'path_confirmed'
            && $candidate['fresh_300s'] === true && $out['positive_affinity'] === true) {
            $out['mechanical_gate'] = 'READY';
            break;
        }
    }
} catch (Throwable $e) {
    if (isset($db) && $db) @pg_query($db, 'ROLLBACK');
    // Keep failure output categorical: never emit DSN, SQL, exception, or secrets.
    $out['query_status'] = $stage;
}
echo json_encode($out, JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR), PHP_EOL;
KAH_PHP
)

php_b64=$(printf '%s' "$php_source" | base64 | tr -d '\r\n')
db_driver=$(cat <<'KAH_DB_DRIVER'
import base64,os,shlex,subprocess,sys
try:
    allowed={'STOBE_DB_HOST','STOBE_DB_PORT','STOBE_DB_NAME','STOBE_DB_USER','STOBE_DB_PASSWORD'}
    required={'STOBE_DB_HOST','STOBE_DB_PORT','STOBE_DB_NAME','STOBE_DB_USER'}
    got={}
    for raw in open('/tmp/stobe-standalone4080/env.sh',encoding='utf-8'):
        line=raw.strip()
        if not line or line.startswith('#') or line.startswith('set '): continue
        if not line.startswith('export '): raise ValueError()
        for part in shlex.split(line[7:],posix=True):
            k,sep,v=part.partition('=')
            if k not in allowed: continue
            if not sep or k in got or any(c in v for c in '$`\r\n\x00') or len(v)>2048: raise ValueError()
            got[k]=v
    if not required.issubset(got): raise ValueError()
    if got['STOBE_DB_HOST']!='/tmp/stobe-standalone4080/socket' or got['STOBE_DB_PORT']!='15434' or got['STOBE_DB_NAME']!='stobe_standalone4080_test' or got['STOBE_DB_USER']!='dwemer': raise ValueError()
    child=dict(os.environ)
    for k in list(child):
        if k in allowed or k.startswith('PG'): child.pop(k,None)
    child.update(got)
    preserve=','.join(sorted(got))
    args=['sudo','-u','www-data','--preserve-env='+preserve,'php','-d','display_errors=0','-d','log_errors=0']
    p=subprocess.run(args,input=base64.b64decode(sys.argv[1],validate=True),env=child,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=15)
    if p.returncode: sys.exit(3)
    sys.stdout.buffer.write(p.stdout)
except Exception: sys.exit(2)
KAH_DB_DRIVER
)
driver_b64=$(printf '%s' "$db_driver" | base64 | tr -d '\r\n')
result=$(MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- bash -lc "set +x; printf '%s' '$driver_b64' | base64 -d | python3 - '$php_b64'" 2>/dev/null) || { echo 'RESULT 4080-CIND-TRAVEL-READINESS FAIL setup=private_db_gate'; exit 2; }
[[ -n "$result" && "$result" != *$'\n'* && "$result" != *$'\r'* ]] || { echo 'RESULT 4080-CIND-TRAVEL-READINESS FAIL output=malformed'; exit 2; }
printf '%s\n' "$result"
