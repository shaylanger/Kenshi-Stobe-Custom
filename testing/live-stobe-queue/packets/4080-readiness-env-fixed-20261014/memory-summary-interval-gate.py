#!/usr/bin/env python3
"""Guarded, private 4080 summary-interval CAS body. Never prints DB env or raw HTTP bodies."""
from __future__ import annotations
import hashlib, json, os, re, shlex, subprocess, sys, time
from pathlib import Path
from urllib.request import urlopen
from urllib.error import URLError, HTTPError

ROOT = Path('/tmp/stobe-standalone4080/site')
DB_PIN = 'stobe_standalone4080_test'
SOURCE_PINS = {
    'lib/memory_helper_functions.php': 'f37f7ba74ac5dc72fa12cd9c2cb36f1932531361a9449459900692c32dcd25d9',
    'lib/settings.php': 'ad208bad81f354539b9086cfb5e90f7534cb374947a2aa6dbb52179cb62bbf3f',
}
OLD_VALUE = '6'
PAUSE_UPDATED_AT = '2026-10-12 19:35:05.446721'
QWEN_BASE = 'http://127.0.0.1:18095'
DB_KEYS = {'STOBE_DB_HOST','STOBE_DB_PORT','STOBE_DB_NAME','STOBE_DB_USER','STOBE_DB_PASSWORD'}
TIME_RE = re.compile(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,6}')


def hashes_match(observed, expected=SOURCE_PINS):
    return all(observed.get(name) == digest for name, digest in expected.items())


def source_pin_status(root=ROOT, expected=SOURCE_PINS):
    try:
        resolved = root.resolve(strict=True)
        if str(resolved) != str(ROOT):
            return False
        observed = {}
        for rel in expected:
            path = resolved / rel
            if path.is_symlink() or not path.is_file():
                return False
            observed[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
        return hashes_match(observed, expected)
    except (OSError, RuntimeError):
        return False


def qwen_slot_is_idle(health_status, health_body, slots_status, slots_body):
    """Accept only health=status ok and exactly slot id 0 with false processing."""
    if health_status != 200 or not isinstance(health_body, dict) or health_body.get('status') != 'ok':
        return False
    if slots_status != 200:
        return False
    records = slots_body.get('slots') if isinstance(slots_body, dict) else None
    if not isinstance(records, list) or len(records) != 1:
        return False
    record = records[0]
    return isinstance(record, dict) and type(record.get('id')) is int and record.get('id') == 0 and record.get('is_processing') is False


def gate_decision(*, db_name, sources_ok, qwen_idle, lock_acquired, mode,
                  value, updated_at, expected_updated_at=None):
    """Pure policy used by local mocks; never performs an update."""
    if not sources_ok:
        return 'source_pin_mismatch'
    if db_name != DB_PIN:
        return 'database_pin_mismatch'
    if not qwen_idle:
        return 'qwen_not_idle'
    if not lock_acquired:
        return 'summary_lock_busy'
    if mode == 'pause':
        return 'cas_ready' if value == OLD_VALUE and updated_at == PAUSE_UPDATED_AT else 'cas_mismatch'
    if mode == 'rollback':
        if value != '720' or not isinstance(expected_updated_at, str) or not TIME_RE.fullmatch(expected_updated_at):
            return 'cas_mismatch'
        return 'cas_ready' if updated_at == expected_updated_at else 'cas_mismatch'
    return 'invalid_mode'


def load_db_env(path='/tmp/stobe-standalone4080/env.sh'):
    values = {}
    for raw in Path(path).read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or line.startswith('set '):
            continue
        if not line.startswith('export '):
            raise ValueError('unsupported_env_syntax')
        for part in shlex.split(line[7:], posix=True):
            key, sep, value = part.partition('=')
            if key not in DB_KEYS:
                continue
            if not sep or key in values or any(ch in value for ch in '$`\r\n\x00') or len(value) > 2048:
                raise ValueError('unsafe_db_env')
            values[key] = value
    if not (DB_KEYS - {'STOBE_DB_PASSWORD'}).issubset(values):
        raise ValueError('missing_db_env')
    child = dict(os.environ)
    for key in DB_KEYS:
        child.pop(key, None)
    child.update(values)
    return child, ','.join(sorted(values))


def get_json(path):
    try:
        with urlopen(QWEN_BASE + path, timeout=2) as response:
            status = int(response.status)
            body = response.read(16385)
        if len(body) > 16384:
            return status, None
        value = json.loads(body.decode('utf-8'))
        return status, value if isinstance(value, dict) else None
    except (URLError, HTTPError, TimeoutError, OSError, ValueError):
        return 0, None


PHP_TRANSACTION = r'''$input=json_decode(stream_get_contents(STDIN),true); if(!is_array($input)){echo json_encode(["status"=>"input_invalid"]);exit(0);} $root="/tmp/stobe-standalone4080/site"; $pins=["lib/memory_helper_functions.php"=>"f37f7ba74ac5dc72fa12cd9c2cb36f1932531361a9449459900692c32dcd25d9","lib/settings.php"=>"ad208bad81f354539b9086cfb5e90f7534cb374947a2aa6dbb52179cb62bbf3f"]; foreach($pins as $rel=>$expected){$path=$root."/".$rel; if(!is_file($path)||is_link($path)||!hash_equals($expected,hash_file("sha256",$path))){echo json_encode(["status"=>"source_pin_mismatch"]);exit(0);}} require_once $root."/lib/playthrough_switching.php"; $c=ptp_connect(); if(!$c){echo json_encode(["status"=>"db_unavailable"]);exit(0);} @pg_query($c,"SET statement_timeout TO 3000"); $identity=pg_query($c,"SELECT current_database() AS db, pg_backend_pid() AS pid, current_setting('application_name') AS app"); $id=$identity?pg_fetch_assoc($identity):null; if(!is_array($id)||($id["db"]??"")!=="stobe_standalone4080_test"){echo json_encode(["status"=>"database_pin_mismatch"]);exit(0);} $mode=$input["mode"]??""; $expectedAt=$input["expected_updated_at"]??""; if(!in_array($mode,["pause","rollback"],true)){echo json_encode(["status"=>"invalid_mode"]);exit(0);} if($mode==="rollback"&&(!is_string($expectedAt)||!preg_match("/^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{1,6}$/",$expectedAt))){echo json_encode(["status"=>"expected_timestamp_invalid"]);exit(0);} $begin=pg_query($c,"BEGIN"); if($begin===false){echo json_encode(["status"=>"transaction_unavailable"]);exit(0);} $lock=pg_query_params($c,"SELECT pg_try_advisory_lock($1) AS acquired",["937463"]); $lockrow=$lock?pg_fetch_assoc($lock):null; $acquired=is_array($lockrow)&&in_array(strtolower(strval($lockrow["acquired"]??"")),["t","true","1"],true); if(!$acquired){@pg_query($c,"ROLLBACK"); echo json_encode(["status"=>"summary_lock_busy","pid"=>intval($id["pid"]??0)]);exit(0);} $expectedValue=$mode==="pause"?"6":"720"; $newValue=$mode==="pause"?"720":"6"; $expectedTime=$mode==="pause"?"2026-10-12 19:35:05.446721":$expectedAt; $sql="UPDATE public.general_settings SET value=$1, updated_at=NOW() WHERE current_database()=$2 AND id=$3 AND value=$4 AND updated_at::text=$5 RETURNING id,value,updated_at::text AS changed_at"; $updated=pg_query_params($c,$sql,[$newValue,"stobe_standalone4080_test","MEMORY_AUTO_CREATE_SUMMARY_INTERVAL",$expectedValue,$expectedTime]); $row=$updated?pg_fetch_assoc($updated):null; $count=$updated?pg_affected_rows($updated):0; if($count!==1||!is_array($row)||($row["id"]??"")!=="MEMORY_AUTO_CREATE_SUMMARY_INTERVAL"||($row["value"]??"")!==$newValue){@pg_query($c,"ROLLBACK");@pg_query_params($c,"SELECT pg_advisory_unlock($1)",["937463"]);echo json_encode(["status"=>$updated===false?"update_error":"cas_mismatch","pid"=>intval($id["pid"]??0)]);exit(0);} if(!pg_query($c,"COMMIT")){@pg_query($c,"ROLLBACK");@pg_query_params($c,"SELECT pg_advisory_unlock($1)",["937463"]);echo json_encode(["status"=>"commit_error","pid"=>intval($id["pid"]??0)]);exit(0);} $unlock=pg_query_params($c,"SELECT pg_advisory_unlock($1) AS unlocked",["937463"]); $unlockrow=$unlock?pg_fetch_assoc($unlock):null; $app=strval($id["app"]??""); if(!preg_match("/^[A-Za-z0-9_.-]{1,64}$/",$app))$app="other"; echo json_encode(["status"=>"updated","mode"=>$mode,"database"=>$id["db"],"pid"=>intval($id["pid"]??0),"application_name"=>$app,"old_value"=>$expectedValue,"new_value"=>$newValue,"updated_at"=>strval($row["changed_at"]??"invalid"),"lock_released"=>is_array($unlockrow)&&in_array(strtolower(strval($unlockrow["unlocked"]??"")),["t","true","1"],true)],JSON_UNESCAPED_SLASHES),PHP_EOL;'''


def run_transaction(mode, expected_at, env, preserve):
    payload = json.dumps({'mode': mode, 'expected_updated_at': expected_at}, separators=(',', ':'))
    try:
        result = subprocess.run(['sudo','-u','www-data','--preserve-env='+preserve,'php','-d','display_errors=0','-d','log_errors=0','-r',PHP_TRANSACTION],
                               input=payload, env=env, capture_output=True, text=True,
                               encoding='utf-8', errors='replace', timeout=6)
    except subprocess.TimeoutExpired:
        return {'status':'php_timeout'}
    except OSError:
        return {'status':'php_launch_error'}
    if result.returncode != 0:
        return {'status':'php_failed','exit_code':int(result.returncode)}
    try:
        value = json.loads(result.stdout.strip())
    except (TypeError, ValueError):
        return {'status':'php_output_invalid'}
    if not isinstance(value, dict) or value.get('status') not in {
        'updated','source_pin_mismatch','db_unavailable','database_pin_mismatch',
        'invalid_mode','expected_timestamp_invalid','transaction_unavailable',
        'summary_lock_busy','update_error','cas_mismatch','commit_error'
    }:
        return {'status':'php_output_unrecognized'}
    return value


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv == ['--self-test']:
        return self_test()
    if len(argv) not in (1, 2) or argv[0] not in ('pause','rollback'):
        print(json.dumps({'status':'invalid_arguments'},separators=(',',':'))); return 2
    mode = argv[0]
    expected_at = argv[1] if len(argv) == 2 else ''
    if mode == 'rollback' and not TIME_RE.fullmatch(expected_at):
        print(json.dumps({'status':'expected_timestamp_invalid'},separators=(',',':'))); return 2
    if mode == 'pause' and expected_at:
        print(json.dumps({'status':'unexpected_timestamp'},separators=(',',':'))); return 2
    if not source_pin_status():
        print(json.dumps({'status':'source_pin_mismatch'},separators=(',',':'))); return 2
    try:
        env, preserve = load_db_env()
    except (OSError, ValueError):
        print(json.dumps({'status':'db_environment_invalid'},separators=(',',':'))); return 2
    # Bounded attempt loop allows a running summary cycle/model request to finish naturally.
    # Each DB attempt uses pg_try_advisory_lock; this body never blocks or kills a producer.
    for attempt in range(1, 16):
        health_status, health = get_json('/health')
        slots_status, slots = get_json('/slots')
        if not qwen_slot_is_idle(health_status, health, slots_status, slots):
            if attempt < 15:
                time.sleep(1)
                continue
            print(json.dumps({'status':'qwen_not_idle','attempts':attempt},separators=(',',':'))); return 3
        result = run_transaction(mode, expected_at, env, preserve)
        result['attempts'] = attempt
        if result.get('status') == 'summary_lock_busy':
            if attempt < 15:
                time.sleep(1)
                continue
            print(json.dumps(result,separators=(',',':'))); return 3
        print(json.dumps(result,separators=(',',':')))
        return 0 if result.get('status') == 'updated' else 4
    print(json.dumps({'status':'bounded_wait_exhausted','attempts':15},separators=(',',':')))
    return 3


def self_test():
    base = {'db_name':DB_PIN,'sources_ok':True,'qwen_idle':True,'lock_acquired':True,
            'mode':'pause','value':'6','updated_at':PAUSE_UPDATED_AT}
    cases = [
        ('pause_ready',{},'cas_ready'),
        ('lock_busy',{'lock_acquired':False},'summary_lock_busy'),
        ('database_mismatch',{'db_name':'other'},'database_pin_mismatch'),
        ('source_invalid',{'sources_ok':False},'source_pin_mismatch'),
        ('qwen_busy',{'qwen_idle':False},'qwen_not_idle'),
        ('cas_stale',{'updated_at':'2026-10-12 19:35:06.000000'},'cas_mismatch'),
    ]
    for name, change, expected in cases:
        values=dict(base);values.update(change)
        got=gate_decision(**values)
        if got != expected: raise AssertionError(f'{name}: {got}')
    rollback=dict(base,mode='rollback',value='720',updated_at='2026-10-14 12:00:00.123456',expected_updated_at='2026-10-14 12:00:00.123456')
    if gate_decision(**rollback) != 'cas_ready': raise AssertionError('rollback_ready')
    rollback['updated_at']='2026-10-14 12:00:01.123456'
    if gate_decision(**rollback) != 'cas_mismatch': raise AssertionError('rollback_cas_stale')
    good_h={'status':200,'body':{'status':'ok'}}
    good_s={'status':200,'body':{'slots':[{'id':0,'is_processing':False}]}}
    if not qwen_slot_is_idle(good_h['status'],good_h['body'],good_s['status'],good_s['body']): raise AssertionError('qwen_idle')
    busy_s={'status':200,'body':{'slots':[{'id':0,'is_processing':True}]}}
    if qwen_slot_is_idle(good_h['status'],good_h['body'],busy_s['status'],busy_s['body']): raise AssertionError('qwen_busy')
    if not hashes_match(SOURCE_PINS): raise AssertionError('source_hash_policy')
    altered=dict(SOURCE_PINS);altered['lib/settings.php']='0'*64
    if hashes_match(altered): raise AssertionError('source_hash_mismatch')
    print('PASS pause/rollback CAS mocks: source pin, DB pin, Qwen idle, advisory lock busy, stale row, rollback timestamp')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
