from pathlib import Path
import re,base64
folder=Path(__file__).resolve().parent
source=(folder/'auth-session-read-once.py').read_text().replace('$out=["auth_token_valid"','$out=["auth_function_present"=>$auth_fn,"auth_token_valid"').replace("('auth_token_valid','auth_character_valid'","('auth_function_present','auth_token_valid','auth_character_valid'")
(folder/'auth-session-read-once-v2.py').write_text(source,encoding='utf-8',newline='\n')
body=(folder/'auth-session-only.sh').read_text()
encoded=base64.b64encode(source.encode()).decode()
body,n=re.subn(r"printf '%s' '[A-Za-z0-9+/=]+' \| base64 -d \| MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 -",f"printf '%s' '{encoded}' | base64 -d | MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 -",body)
assert n==1
(folder/'auth-session-only-v2.sh').write_text(body,encoding='utf-8',newline='\n')
