#!/bin/bash
# shadow-say.sh <H|S> <batch_id>   (decision JSON on stdin). See shadow_say.py for the schema.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x /c/Users/Shay/AppData/Local/Programs/Python/Python312/python.exe ]; then PY=/c/Users/Shay/AppData/Local/Programs/Python/Python312/python.exe
elif [ -x /mnt/c/Users/Shay/AppData/Local/Programs/Python/Python312/python.exe ]; then PY=/mnt/c/Users/Shay/AppData/Local/Programs/Python/Python312/python.exe
else PY=python.exe; fi
exec "$PY" -I "$(cd "$DIR" && (cygpath -w "$DIR" 2>/dev/null || wslpath -w "$DIR" 2>/dev/null || echo "$DIR"))\\shadow_say.py" "$@"
