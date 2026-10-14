#!/usr/bin/env bash
# Fixed, read-only, allowlisted source excerpt; never print whole source lines.
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0
readonly MAX_MATCH_ROWS=100
MATCH_ROWS=0

emit_match() {
  local rel="$1" line_no="$2" token="$3"
  if [[ "$MATCH_ROWS" -ge "$MAX_MATCH_ROWS" ]]; then
    printf 'FAIL=match_output_limit LIMIT=%s\n' "$MAX_MATCH_ROWS"
    return 1
  fi
  MATCH_ROWS=$((MATCH_ROWS + 1))
  printf 'MATCH_FILE=%s TOKEN=%s:%s\n' "$rel" "$line_no" "$token"
}

emit_matches() {
  local rel="$1" path="$2" source_line line_no=0 found=0
  while IFS= read -r source_line || [[ -n "$source_line" ]]; do
    line_no=$((line_no + 1))
    if [[ "$source_line" == *'/var/lib/stobe'* ]]; then
      emit_match "$rel" "$line_no" '/var/lib/stobe' || return $?
      found=1
    fi
    if [[ "$source_line" == *'stobe_negotiation_'* ]]; then
      emit_match "$rel" "$line_no" 'stobe_negotiation_' || return $?
      found=1
    fi
    if [[ "$source_line" == *'sys_get_temp_dir'* ]]; then
      emit_match "$rel" "$line_no" 'sys_get_temp_dir' || return $?
      found=1
    fi
  done < "$path" || { printf 'FAIL=read_error FILE=%s\n' "$rel"; return 1; }
  if [[ "$found" -eq 0 ]]; then
    printf 'MATCH=none FILE=%s\n' "$rel"
  fi
}

pinned_blob() {
  local root="$1" commit="$2" rel="$3" row metadata path mode type oid blob
  row=$(git --no-optional-locks -C "$root" ls-tree --full-tree "$commit" -- "$rel" 2>/dev/null) || {
    printf 'FAIL=git_tree_lookup FILE=%s\n' "$rel"
    return 1
  }
  if [[ -z "$row" ]]; then
    printf 'FAIL=path_absent_from_pinned_tree FILE=%s\n' "$rel"
    return 1
  fi
  IFS=$'\t' read -r metadata path <<< "$row"
  IFS=' ' read -r mode type oid <<< "$metadata"
  if [[ "$path" != "$rel" || "$type" != 'blob' || ! "$oid" =~ ^[0-9a-f]{40,64}$ ]]; then
    printf 'FAIL=invalid_pinned_tree_entry FILE=%s\n' "$rel"
    return 1
  fi
  blob=$(git --no-optional-locks -C "$root" rev-parse --verify "$commit:$rel" 2>/dev/null) || {
    printf 'FAIL=blob_unavailable_at_pinned_commit FILE=%s\n' "$rel"
    return 1
  }
  if [[ "$blob" != "$oid" ]]; then
    printf 'FAIL=pinned_blob_mismatch FILE=%s\n' "$rel"
    return 1
  fi
  if ! GIT_NO_LAZY_FETCH=1 git --no-optional-locks -C "$root" cat-file -e "$blob" 2>/dev/null; then
    printf 'FAIL=blob_object_unavailable_at_pinned_commit FILE=%s\n' "$rel"
    return 1
  fi
  printf 'BLOB=%s FILE=%s\n' "$blob" "$rel"
}

if [[ "${STOBE_PACKET_FIXTURE:-0}" == '1' ]]; then
  emit_matches fixture "$STOBE_PACKET_FIXTURE_PATH" || exit $?
  exit 0
fi

if [[ "${STOBE_PACKET_GIT_FIXTURE:-0}" == '1' ]]; then
  pinned_blob "$STOBE_PACKET_GIT_FIXTURE_ROOT" "$STOBE_PACKET_GIT_FIXTURE_COMMIT" "$STOBE_PACKET_GIT_FIXTURE_PATH"
  exit $?
fi

printf 'PACKET=5090_SOURCE_EXCERPTS_V1\nROUTE=local-wsl\nDISTRO=DwemerAI4Skyrim3\n'

inspect_root() {
  local label="$1" root="$2" expected_commit="$3" canonical commit rel path resolved digest blob blob_result failure
  local files=(interaction.php lib/playthrough_preferences.php lib/playthrough_runtime.php lib/travel_companionship.php lib/chat_helper_functions.php lib/activity/ActivityService.php)
  printf 'ROOT_BEGIN=%s\n' "$label"
  if [[ ! -d "$root" || -L "$root" ]]; then
    printf 'FAIL=missing_or_symlink_root root=%s\n' "$label"
    return 1
  fi
  canonical=$(realpath -e -- "$root" 2>/dev/null) || { printf 'FAIL=canonical_root_unavailable root=%s\n' "$label"; return 1; }
  if [[ "$canonical" != "$root" ]]; then printf 'FAIL=root_path_mismatch root=%s\n' "$label"; return 1; fi
  commit=$(git --no-optional-locks -C "$root" rev-parse --verify HEAD 2>/dev/null) || { printf 'FAIL=git_commit_unavailable root=%s\n' "$label"; return 1; }
  if [[ "$commit" != "$expected_commit" ]]; then printf 'FAIL=commit_mismatch root=%s\n' "$label"; return 1; fi
  printf 'ROOT=%s CANONICAL=%s COMMIT=%s\n' "$label" "$root" "$commit"
  for rel in "${files[@]}"; do
    path="$root/$rel"
    if [[ ! -f "$path" || -L "$path" ]]; then printf 'FAIL=missing_or_symlink_file root=%s file=%s\n' "$label" "$rel"; return 1; fi
    resolved=$(realpath -e -- "$path" 2>/dev/null) || { printf 'FAIL=unresolved_file root=%s file=%s\n' "$label" "$rel"; return 1; }
    if [[ "$resolved" != "$root/$rel" ]]; then printf 'FAIL=file_path_mismatch root=%s file=%s\n' "$label" "$rel"; return 1; fi
    blob_result=$(pinned_blob "$root" "$commit" "$rel") || {
      failure=${blob_result%% FILE=*}
      printf '%s root=%s file=%s\n' "$failure" "$label" "$rel"
      return 1
    }
    blob=${blob_result#BLOB=}
    blob=${blob%% FILE=*}
    digest=$(sha256sum -- "$path" 2>/dev/null) || { printf 'FAIL=source_hash root=%s file=%s\n' "$label" "$rel"; return 1; }
    digest=${digest%% *}
    if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then printf 'FAIL=invalid_source_hash root=%s file=%s\n' "$label" "$rel"; return 1; fi
    printf 'SOURCE=%s SHA256=%s GIT_BLOB=%s\n' "$rel" "$digest" "$blob"
    if git --no-optional-locks -C "$root" diff --quiet "$commit" -- "$rel"; then :; else printf 'FAIL=working_tree_diff root=%s file=%s\n' "$label" "$rel"; return 1; fi
    # Emit only the matched token and its line number: no source line or adjacent context.
    emit_matches "$rel" "$path" || return $?
  done
  printf 'ROOT_END=%s\n' "$label"
}

inspect_root live /var/www/html/StobeServer 4722ddd96d838e84ddb9a49da0ee893f45bcaab7 || exit $?
inspect_root merge /root/stobe-work/ss-merge 7aff5ba605a956d33accc8080f712dfba4015246 || exit $?
printf 'THROTTLE_FILE=lib/negotiation_engine.php STATUS=NOT_IN_ALLOWLIST_NOT_INSPECTED\n'
printf 'PROTECTED_FILE=lib/playthrough_switching.php STATUS=EXCLUDED_NOT_INSPECTED\n'
printf 'END=5090_SOURCE_EXCERPTS_V1\n'
