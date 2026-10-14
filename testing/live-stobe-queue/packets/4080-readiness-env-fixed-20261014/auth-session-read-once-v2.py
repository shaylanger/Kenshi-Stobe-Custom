import json
import os
import re
import shlex
import subprocess
import sys


PHP_READ = r'''require "/tmp/stobe-standalone4080/site/lib/playthrough_switching.php";
$c=ptp_connect();
$s=ptr_read($c,"PLAYTHROUGH_SESSION",[]);
$d="/tmp/stobe-standalone4080/site/log/playthrough_runtime/";
$g=is_file($d."generation")?trim(file_get_contents($d."generation")):"";
$r=is_file($d."manager.ready")?trim(file_get_contents($d."manager.ready")):"";
$load=(string)($s["load_id"]??"");
$token=$s["token"]??null;
$character=$s["character_id"]??null;
$token_valid=is_string($token)&&preg_match('/^[a-f0-9]{32}$/D',$token)===1;
$character_valid=is_string($character)&&preg_match('/^[a-f0-9]{32}$/D',$character)===1;
$auth_fn=function_exists('pas_receipt_valid');
$campaign=pg_fetch_assoc(pth_query($c,"SELECT value FROM public.conf_opts WHERE id='PLAYTHROUGH_CAMPAIGN_ID'"));
$campaign_match=$character_valid&&is_string($campaign["value"]??null)&&hash_equals($character,$campaign["value"]);
$switch_hash=hash_file('sha256','/tmp/stobe-standalone4080/site/lib/playthrough_switching.php');
$out=["auth_function_present"=>$auth_fn,"auth_token_valid"=>$token_valid,"auth_character_valid"=>$character_valid,"stored_receipt_valid"=>$auth_fn&&pas_receipt_valid($s,$token),"campaign_identity_matches"=>$campaign_match,"switching_source_sha256"=>$switch_hash,"session_present"=>!empty($s),"status"=>$s["status"]??null,
      "gamets"=>$s["gamets"]??null,"load_id_sha256"=>hash("sha256",$load),
      "generation_present"=>$g!=="","manager_ready_matches"=>$g!==""&&hash_equals($g,$r)];
echo json_encode($out,JSON_UNESCAPED_SLASHES),PHP_EOL;'''


def _stderr_text(stderr):
    if isinstance(stderr, bytes):
        return stderr.decode("utf-8", errors="replace")
    return stderr if isinstance(stderr, str) else ""


def _stderr_class(stderr):
    text = _stderr_text(stderr).lower()
    if not text.strip():
        return "empty"
    if re.search(r"permission denied|operation not permitted|not permitted", text):
        return "permission_denied"
    if re.search(r"password is required|authentication failure|no tty present|a terminal is required|askpass", text):
        return "authentication_required"
    if re.search(r"no such file or directory|command not found|could not open input file", text):
        return "missing_file_or_command"
    if "connection refused" in text:
        return "connection_refused"
    if re.search(r"timed out|timeout", text):
        return "timeout"
    if re.search(r"network is unreachable|host is down|could not resolve|name or service not known", text):
        return "network_error"
    if re.search(r"php (?:warning|fatal error|parse error)|fatal error|parse error", text):
        return "php_error"
    if re.search(r"(?:^|\n)(?:bash|sh):", text):
        return "shell_error"
    return "other"


def _stderr_diagnostic(stderr):
    text = _stderr_text(stderr)
    return {
        "stderr_captured": bool(text.strip()),
        "stderr_class": _stderr_class(text),
        "stderr_line_count": sum(1 for line in text.splitlines() if line.strip()),
    }


def _failure(exit_code, stderr, failure_kind):
    result = {
        "result": "FAIL",
        "exit_code": int(exit_code),
        "failure_kind": failure_kind,
    }
    result.update(_stderr_diagnostic(stderr))
    return result


def _safe_session_payload(value):
    if not isinstance(value, dict):
        return None

    session_present = value.get("session_present")
    generation_present = value.get("generation_present")
    manager_ready_matches = value.get("manager_ready_matches")
    if not all(isinstance(flag, bool) for flag in (session_present, generation_present, manager_ready_matches)):
        return None

    status = value.get("status")
    allowed_statuses = {"ready", "pending", "expired", "missing", "error", "blocked", "loading"}
    if status is not None:
        if not isinstance(status, str):
            return None
        status = status.strip().lower()
        status = status if status in allowed_statuses else "other"

    gamets = value.get("gamets")
    if isinstance(gamets, str) and re.fullmatch(r"\d{1,19}", gamets):
        gamets = int(gamets)
    if gamets is not None and (type(gamets) is not int or gamets < 0):
        return None

    load_id_sha256 = value.get("load_id_sha256")
    if not isinstance(load_id_sha256, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", load_id_sha256):
        return None

    # Explicit allowlist: raw load ids, tokens, environment fields, and any
    # unexpected server values never leave this process.
    return {
        "session_present": session_present,
        "status": status,
        "gamets": gamets,
        "load_id_sha256": load_id_sha256.lower(),
        "generation_present": generation_present,
        "manager_ready_matches": manager_ready_matches,
    }


def load_db_env(path='/tmp/stobe-standalone4080/env.sh'):
    keys={'STOBE_DB_HOST','STOBE_DB_PORT','STOBE_DB_NAME','STOBE_DB_USER','STOBE_DB_PASSWORD'}
    settings={}
    with open(path, encoding='utf-8') as source:
        for line in source:
            line=line.strip()
            if not line or line.startswith('#') or line.startswith('set '):
                continue
            if not line.startswith('export '):
                raise ValueError('unsupported syntax')
            for part in shlex.split(line[7:],posix=True):
                key,sep,value=part.partition('=')
                if key not in keys:
                    continue
                if not sep or key in settings or any(c in value for c in '$`\r\n\x00') or len(value)>2048:
                    raise ValueError('unsafe setting')
                settings[key]=value
    if not (keys-{'STOBE_DB_PASSWORD'}).issubset(settings):
        raise ValueError('missing settings')
    child=dict(os.environ)
    for key in keys:
        child.pop(key,None)
    child.update(settings)
    return child, ','.join(sorted(settings))


def read_session(run_subprocess=subprocess.run, env_loader=load_db_env):
    try:
        child, preserve = env_loader()
    except (OSError, ValueError):
        return _failure(26, '', 'db_environment_invalid')
    try:
        run = run_subprocess(
            ['sudo','-u','www-data','--preserve-env='+preserve,'php','-d','display_errors=0','-d','log_errors=0','-r',PHP_READ],
            env=child, capture_output=True, text=True,
            encoding="utf-8", errors="replace", timeout=20,
        )
    except subprocess.TimeoutExpired as exc:
        return _failure(124, exc.stderr, "timeout")
    except OSError:
        # Do not serialize exception text: it may include the command or paths.
        return _failure(127, "", "process_launch_error")

    if run.returncode != 0:
        return _failure(run.returncode, run.stderr, "subprocess_failed")
    try:
        parsed = json.loads(run.stdout.strip())
    except (TypeError, ValueError):
        return _failure(2, run.stderr, "invalid_json")
    safe = _safe_session_payload(parsed)
    if safe is None:
        return _failure(2, run.stderr, "invalid_session_payload")
    for key in ('auth_function_present','auth_token_valid','auth_character_valid','stored_receipt_valid','campaign_identity_matches'):
        if type(parsed.get(key)) is not bool:
            return _failure(2, run.stderr, 'invalid_auth_payload')
        safe[key]=parsed[key]
    fingerprint=parsed.get('switching_source_sha256')
    if not isinstance(fingerprint,str) or not re.fullmatch(r'[a-f0-9]{64}',fingerprint):
        return _failure(2, run.stderr, 'invalid_auth_payload')
    safe['switching_source_sha256']=fingerprint
    return safe


def main():
    result = read_session()
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return int(result.get("exit_code", 0)) or (1 if result.get("result") == "FAIL" else 0)


if __name__ == "__main__":
    sys.exit(main())
