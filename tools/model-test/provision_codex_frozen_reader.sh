#!/usr/bin/env bash
# STAGED ONLY: administrator-reviewed setup for isolated stobe_frozen reads.
# Never run this as a benchmark tool or against database `stobe`.
set -euo pipefail

DB_NAME=stobe_frozen
ROLE=codex_frozen_reader
CREDENTIALS=/root/.config/kenshi-model-test/frozen-reader.json
SQL_FILE=/mnt/c/KenshiModding/tools/model-test/provision_codex_frozen_reader.sql

actual=$(sudo -u postgres psql -X -At -d "$DB_NAME" -c 'select current_database()')
[[ "$actual" == "$DB_NAME" ]] || { echo 'refusing: target database mismatch' >&2; exit 2; }
foreign_tables=$(sudo -u postgres psql -X -At -d "$DB_NAME" -c 'select count(*) from pg_foreign_table')
echo "FROZEN_FOREIGN_TABLES $foreign_tables"
[[ "$foreign_tables" == 0 ]] || { echo 'refusing: frozen DB contains foreign tables' >&2; exit 2; }
sudo /usr/bin/psql --version >/dev/null || {
  echo 'fixed /usr/bin/psql client missing; setup stops without installing dependencies' >&2
  exit 2
}
role_exists=$(sudo -u postgres psql -X -At -d postgres -c "select count(*) from pg_roles where rolname='$ROLE'")
if [[ "$role_exists" == 1 ]]; then
  [[ -f "$CREDENTIALS" ]] || { echo "role exists but its private credential file is missing; manual review required" >&2; exit 2; }
  [[ $(stat -c '%a' "$CREDENTIALS") == 600 ]] || { echo 'credential file must be mode 0600' >&2; exit 2; }
  result=$(sudo /usr/bin/python3 /mnt/c/KenshiModding/tools/model-test/codex_db_broker.py <<<'{"preflight":true}')
  [[ "$result" == *'"database": "stobe_frozen"'* && "$result" == *'"reader_safe": true'* ]] || {
    echo 'existing reader failed read-only role/privilege preflight' >&2; exit 2;
  }
  echo "Existing $ROLE credential, role-attribute, and effective read-only privilege checks passed for $DB_NAME; no changes made."
  exit 0
fi

[[ ! -e "$CREDENTIALS" ]] || { echo 'credential file exists but database role does not; manual review required' >&2; exit 2; }
sudo -u postgres pg_isready -h 127.0.0.1 -p 5432 >/dev/null || {
  echo 'PostgreSQL TCP localhost is not accepting connections; inspect existing configuration without changing it' >&2
  exit 2
}
if [[ ! -d /root/.config/kenshi-model-test ]]; then
  sudo install -d -o root -g root -m 0700 /root/.config/kenshi-model-test
else
  [[ $(stat -c '%a:%u' /root/.config/kenshi-model-test) == 700:0 ]] || {
    echo 'dedicated private credential directory exists with unexpected owner/mode' >&2
    exit 2
  }
fi

CODEX_FROZEN_READER_PASSWORD=$(python3 -c 'import secrets; print(secrets.token_urlsafe(48))')
export CODEX_FROZEN_READER_PASSWORD
python3 - <<'PY' | sudo install -o root -g root -m 0600 /dev/stdin "$CREDENTIALS"
import json, os
print(json.dumps({"host":"127.0.0.1", "port":5432,
                  "user":"codex_frozen_reader", "password":os.environ["CODEX_FROZEN_READER_PASSWORD"],
                  "dbname":"stobe_frozen"}, separators=(",", ":")))
PY
sql_complete=0
cleanup_uncommitted_credential() {
  if [[ "$sql_complete" == 0 ]]; then sudo rm -f -- "$CREDENTIALS"; fi
}
trap cleanup_uncommitted_credential EXIT
sudo --preserve-env=CODEX_FROZEN_READER_PASSWORD -u postgres psql -X -v ON_ERROR_STOP=1 -d "$DB_NAME" -f "$SQL_FILE"
sql_complete=1
unset CODEX_FROZEN_READER_PASSWORD
result=$(sudo /usr/bin/python3 /mnt/c/KenshiModding/tools/model-test/codex_db_broker.py <<<'{"preflight":true}')
[[ "$result" == *'"database": "stobe_frozen"'* && "$result" == *'"reader_safe": true'* ]] || {
  echo 'reader created but fixed broker preflight failed; stop and repair setup before any model run' >&2
  exit 2
}
echo "Provisioned $ROLE for $DB_NAME. Review role grants and credential file before enabling MCP."
