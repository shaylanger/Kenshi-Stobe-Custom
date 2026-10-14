from pathlib import Path
import base64,re,hashlib
folder=Path(__file__).resolve().parent
root=folder.parents[3]
base=root/'pending-fixes/rig4080-validation/chat007-session-reader-stream.review.sh'
assert hashlib.sha256(base.read_bytes()).hexdigest().upper()=='D2127D7B2B5830D52074C9B4B971C20CC5E46A20AF3CDDF0B6D92DFAA987CFD2'
body=base.read_text()
reader=folder/'chat007-session-read-once.py'
encoded=base64.b64encode(reader.read_bytes()).decode()
body,n=re.subn(r"printf '%s' '[A-Za-z0-9+/=]+' \| base64 -d \| MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 -",f"printf '%s' '{encoded}' | base64 -d | MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- python3 -",body)
assert n==1
diag=(folder.parent/'4080-session-type-bound-20261014/body.sh').read_text()
guard=re.search(r"listener_guard=\$\(cat <<'KAH_LISTENER'\n(.*?)\nKAH_LISTENER\n\)",diag,re.S).group(1)
guard64=base64.b64encode(guard.encode()).decode()
marker="printf '\\n=== READY SESSION GENERATION (SANITIZED) ===\\n'"
body=body.replace(marker, f"MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -- bash -lc \"printf '%s' '{guard64}' | base64 -d | bash\"\n"+marker)
assert body.count(guard64)==1
(folder/'body.sh').write_text(body,encoding='utf-8',newline='\n')
print('candidate stream generated with exact embedded corrected reader and strict private listener/root guard')
