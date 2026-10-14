export RIG=4080 KAH_INSTANCE=3
export KENSHI_DIR=/c/KenshiInst/3 KDIR=/c/KenshiInst/3
export KAH_DIR='C:\KenshiInst\3\mods\AutomationHarness'
. /c/KenshiModding/tools/automation/rig-env.sh
set -euo pipefail


# Guard the isolated instance-3 route and require the harness inbox to be clear.
# The guard's status text is intentionally suppressed; stdout is reserved for
# the single JSON diagnostic object.
rig4080_i3_preflight >/dev/null 2>&1

php_source=$(cat <<'KAH_PHP'
<?php
$baseLevel = ob_get_level();
ob_start();
error_reporting(0);
set_error_handler(static function () { return true; });

$out = [
    'php_version' => PHP_VERSION,
    'source_sha256' => '',
    'arguments' => kahUnknownArgumentTypes(),
    'result' => 'other_error',
];

function kahSafeType($value): string {
    $type = get_debug_type($value);
    if ($type === 'string') return 'string';
    if ($type === 'int') return 'integer';
    if ($type === 'bool') return 'boolean';
    if ($type === 'float') return 'double';
    if ($type === 'null') return 'NULL';
    if ($type === 'array') return 'array';
    if (is_object($value)) return 'object';
    if (is_resource($value)) return 'resource';
    return 'unknown';
}

function kahUnknownArgumentTypes(): array {
    return [
        ['role' => 'connection', 'index' => 1, 'type' => 'unknown'],
        ['role' => 'query', 'index' => 2, 'type' => 'unknown'],
        ['role' => 'params', 'index' => 3, 'type' => 'unknown'],
    ];
}

function kahPgArgumentTypes(Throwable $error): ?array {
    foreach ($error->getTrace() as $frame) {
        if (($frame['function'] ?? null) !== 'pg_query_params') continue;
        if (!array_key_exists('args', $frame) || !is_array($frame['args']) || count($frame['args']) < 3) {
            return null;
        }
        return [
            ['role' => 'connection', 'index' => 1, 'type' => kahSafeType($frame['args'][0])],
            ['role' => 'query', 'index' => 2, 'type' => kahSafeType($frame['args'][1])],
            ['role' => 'params', 'index' => 3, 'type' => kahSafeType($frame['args'][2])],
        ];
    }
    return null;
}

try {
    require '/tmp/stobe-standalone4080/site/lib/playthrough_switching.php';

    // Hash the exact loaded PHP file containing ptr_query's pg_query_params
    // call boundary. The path and filename are never included in output.
    $sourcePath = (new ReflectionFunction('ptr_query'))->getFileName();
    $expectedSource = '/tmp/stobe-standalone4080/site/lib/playthrough_retention.php';
    if (!is_string($sourcePath) || realpath($sourcePath) !== $expectedSource || is_link($expectedSource)) {
        while (ob_get_level() > $baseLevel) ob_end_clean();
        exit(2);
    }
    $sourceHash = @hash_file('sha256', $expectedSource);
    if (!is_string($sourceHash) || !preg_match('/\A[0-9a-f]{64}\z/', $sourceHash)) {
        while (ob_get_level() > $baseLevel) ob_end_clean();
        exit(2);
    }
    $out['source_sha256'] = $sourceHash;

    // Exception traces must retain call arguments for in-process type-only
    // classification. If PHP cannot provide that, stop before the query.
    $ignoreArgs = ini_get('zend.exception_ignore_args');
    if (!function_exists('get_debug_type') || !in_array($ignoreArgs, ['0', 'Off', 'off'], true)) {
        $out['result'] = 'other_error';
    } else {
        $connection = ptp_connect();
        $session = ptr_read($connection, 'PLAYTHROUGH_SESSION', []);
        unset($session, $connection);
        $out['result'] = 'query_ok';
    }
} catch (TypeError $error) {
    $argumentTypes = kahPgArgumentTypes($error);
    if ($argumentTypes === null) {
        // Fail closed: never infer types from the exception text or another
        // stack frame when the actual internal-call arguments are unavailable.
        $out['result'] = 'other_error';
    } else {
        $out['arguments'] = $argumentTypes;
        $out['result'] = 'type_error';
    }
} catch (Throwable $error) {
    // Do not expose the exception class, message, path, SQL, or stack.
    $out['result'] = 'other_error';
}

if (!preg_match('/\A[0-9a-f]{64}\z/', $out['source_sha256'])) {
    while (ob_get_level() > $baseLevel) ob_end_clean();
    exit(2);
}
while (ob_get_level() > $baseLevel) ob_end_clean();
echo json_encode($out, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), PHP_EOL;
KAH_PHP
)

php_b64=$(printf '%s' "$php_source" | base64 | tr -d '\r\n')
listener_guard=$(cat <<'KAH_LISTENER'
set -euo pipefail
listener_lines=$(ss -H -ltnp 'sport = :18084')
[[ -n "$listener_lines" && "$listener_lines" != *$'\n'* && "$listener_lines" == *'127.0.0.1:18084'* ]] || exit 21
mapfile -t listener_pids < <(printf '%s\n' "$listener_lines" | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
[[ ${#listener_pids[@]} -ge 1 ]] || exit 22
for listener_pid in "${listener_pids[@]}"; do
  [[ "$listener_pid" =~ ^[0-9]+$ ]] || exit 23
  listener_argv=$(ps -p "$listener_pid" -o args= | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [[ "$listener_argv" == 'php -S 127.0.0.1:18084 -t /tmp/stobe-standalone4080/site' ]] || exit 24
done
[[ "$(realpath -e /tmp/stobe-standalone4080/site)" == /tmp/stobe-standalone4080/site ]] || exit 25
KAH_LISTENER
)
listener_guard_b64=$(printf '%s' "$listener_guard" | base64 | tr -d '\r\n')
db_driver=$(cat <<'KAH_DB_DRIVER'
import base64,os,re,shlex,subprocess,sys
try:
    keys={'STOBE_DB_HOST','STOBE_DB_PORT','STOBE_DB_NAME','STOBE_DB_USER','STOBE_DB_PASSWORD'}
    required=keys-{'STOBE_DB_PASSWORD'}
    settings={}
    for line in open('/tmp/stobe-standalone4080/env.sh',encoding='utf-8'):
        line=line.strip()
        if not line or line.startswith('#') or line.startswith('set '): continue
        if not line.startswith('export '):
            raise ValueError('unsupported syntax')
        for part in shlex.split(line[7:],posix=True):
            key,sep,value=part.partition('=')
            if key not in keys: continue
            if not sep or key in settings or any(c in value for c in '$`\r\n\x00') or len(value)>2048:
                raise ValueError('unsafe setting')
            settings[key]=value
    if not required.issubset(settings): raise ValueError('missing settings')
    child=dict(os.environ)
    for key in keys: child.pop(key,None)
    child.update(settings)
    preserve=','.join(sorted(settings))
    args=['sudo','-u','www-data','--preserve-env='+preserve,'php','-d','display_errors=0','-d','log_errors=0','-d','zend.exception_ignore_args=0']
    result=subprocess.run(args,input=base64.b64decode(sys.argv[1],validate=True),env=child,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
    if result.returncode: sys.exit(27)
    sys.stdout.buffer.write(result.stdout)
except Exception:
    sys.exit(26)
KAH_DB_DRIVER
)
db_driver_b64=$(printf '%s' "$db_driver" | base64 | tr -d '\r\n')
wsl_command="set +x; printf '%s' '$listener_guard_b64' | base64 -d | bash || exit; printf '%s' '$db_driver_b64' | base64 -d | python3 - '$php_b64'"
json_line=$(MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- bash -lc "$wsl_command" 2>/dev/null) || exit 2

# Reject any unexpected stdout or extra lines instead of forwarding it.
[[ -n "$json_line" && "$json_line" != *$'\n'* && "$json_line" != *$'\r'* ]] || exit 2
printf '%s\n' "$json_line"
