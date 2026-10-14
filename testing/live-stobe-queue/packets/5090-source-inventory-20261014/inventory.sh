#!/usr/bin/env bash
# Read-only, allowlisted source-provenance inventory. Exact 5090 host only.
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0

printf 'PACKET=5090_SOURCE_INVENTORY_V1\nROUTE=local-wsl\nDISTRO=DwemerAI4Skyrim3\n'

hash_file() {
  local target="$1" raw digest
  raw=$(sha256sum -- "$target" 2>/dev/null) || return 1
  digest=${raw%% *}
  [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  printf '%s' "$digest"
}

inspect_root() {
  local label="$1" expected="$2" root canonical repo_root commit rel path resolved digest
  printf 'ROOT_BEGIN=%s\n' "$label"
  if [[ ! -d "$expected" || -L "$expected" ]]; then
    printf 'ROOT=%s EXISTS=no CANONICAL=unavailable REPO=unknown COMMIT=unavailable\n' "$label"
    printf 'ROOT_END=%s\n' "$label"
    return
  fi
  canonical=$(realpath -e -- "$expected" 2>/dev/null) || canonical=''
  if [[ "$canonical" != "$expected" ]]; then
    printf 'ROOT=%s EXISTS=yes CANONICAL_PATH_MISMATCH REPO=unknown COMMIT=unavailable\n' "$label"
    printf 'ROOT_END=%s\n' "$label"
    return
  fi
  root="$canonical"
  repo='no'; repo_root=''; commit=''
  if git --no-optional-locks -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo='yes'
    repo_root=$(git --no-optional-locks -C "$root" rev-parse --show-toplevel 2>/dev/null) || repo_root=''
    commit=$(git --no-optional-locks -C "$root" rev-parse --verify HEAD 2>/dev/null) || commit=''
    if [[ "$repo_root" != "$root" || ! "$commit" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
      printf 'ROOT=%s EXISTS=yes CANONICAL=%s REPO=metadata-fail COMMIT=unavailable\n' "$label" "$root"
      printf 'ROOT_END=%s\n' "$label"
      return
    fi
  fi
  printf 'ROOT=%s EXISTS=yes CANONICAL=%s REPO=%s COMMIT=%s\n' "$label" "$root" "$repo" "${commit:-none}"

  # Fixed manifest allowlist; report only filenames and hashes, never contents.
  for rel in SOURCE-MANIFEST.json A9-BASELINE-SOURCE-MANIFEST.json MANIFEST.md server-manifest.json; do
    path="$root/$rel"
    if [[ -f "$path" && ! -L "$path" ]]; then
      resolved=$(realpath -e -- "$path" 2>/dev/null) || resolved=''
      if [[ "$resolved" != "$root/$rel" ]]; then
        printf 'ROOT=%s METADATA_FAIL=manifest_path_escape_or_unresolved\n' "$label"
        return 2
      fi
      digest=$(hash_file "$resolved") || { printf 'ROOT=%s METADATA_FAIL=manifest_hash\n' "$label"; return 2; }
      printf 'MANIFEST=%s SHA256=%s\n' "$rel" "$digest"
    else
      printf 'MANIFEST=%s PRESENT=no SHA256=unavailable\n' "$rel"
    fi
  done

  # Small required-source allowlist; no directory enumeration or source reads.
  for rel in interaction.php lib/playthrough_preferences.php lib/playthrough_runtime.php lib/playthrough_switching.php lib/travel_companionship.php lib/chat_helper_functions.php lib/activity/ActivityService.php; do
    path="$root/$rel"
    if [[ -f "$path" && ! -L "$path" ]]; then
      resolved=$(realpath -e -- "$path" 2>/dev/null) || resolved=''
      if [[ "$resolved" != "$root/$rel" ]]; then
        printf 'ROOT=%s METADATA_FAIL=source_path_escape_or_unresolved\n' "$label"
        return 2
      fi
      digest=$(hash_file "$resolved") || { printf 'ROOT=%s METADATA_FAIL=source_hash\n' "$label"; return 2; }
      printf 'SOURCE=%s PRESENT=yes SHA256=%s\n' "$rel" "$digest"
    else
      printf 'SOURCE=%s PRESENT=no SHA256=unavailable\n' "$rel"
    fi
  done
  printf 'ROOT_END=%s\n' "$label"
}

inspect_root live /var/www/html/StobeServer || exit $?
inspect_root merge /root/stobe-work/ss-merge || exit $?
printf 'END=5090_SOURCE_INVENTORY_V1\n'
