from pathlib import Path
import re,base64
folder=Path(__file__).resolve().parent
source=(folder/'chat007-session-read-once.py').read_text()
source=source.replace('$out=["session_present"', '''$token=$s["token"]??null;
$character=$s["character_id"]??null;
$token_valid=is_string($token)&&preg_match('/^[a-f0-9]{32}$/D',$token)===1;
$character_valid=is_string($character)&&preg_match('/^[a-f0-9]{32}$/D',$character)===1;
$auth_fn=function_exists('pas_receipt_valid');
$campaign=pg_fetch_assoc(pth_query($c,"SELECT value FROM public.conf_opts WHERE id='PLAYTHROUGH_CAMPAIGN_ID'"));
$campaign_match=$character_valid&&is_string($campaign["value"]??null)&&hash_equals($character,$campaign["value"]);
$switch_hash=hash_file('sha256','/tmp/stobe-standalone4080/site/lib/playthrough_switching.php');
$out=["auth_token_valid"=>$token_valid,"auth_character_valid"=>$character_valid,"stored_receipt_valid"=>$auth_fn&&pas_receipt_valid($s,$token),"campaign_identity_matches"=>$campaign_match,"switching_source_sha256"=>$switch_hash,"session_present"''')
source=source.replace('    return safe\n', '''    for key in ('auth_token_valid','auth_character_valid','stored_receipt_valid','campaign_identity_matches'):
        if type(parsed.get(key)) is not bool:
            return _failure(2, run.stderr, 'invalid_auth_payload')
        safe[key]=parsed[key]
    fingerprint=parsed.get('switching_source_sha256')
    if not isinstance(fingerprint,str) or not re.fullmatch(r'[a-f0-9]{64}',fingerprint):
        return _failure(2, run.stderr, 'invalid_auth_payload')
    safe['switching_source_sha256']=fingerprint
    return safe
''')
(folder/'auth-session-read-once.py').write_text(source,encoding='utf-8',newline='\n')
body=(folder/'session-only.sh').read_text()
encoded=base64.b64encode(source.encode()).decode()
body,n=re.subn(r"printf '%s' '[A-Za-z0-9+/=]+' \| base64 -d \| MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 -",f"printf '%s' '{encoded}' | base64 -d | MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 -",body)
assert n==1
(folder/'auth-session-only.sh').write_text(body,encoding='utf-8',newline='\n')
print('auth reader generated: stored session booleans/source fingerprint only; does not prove native request header')
