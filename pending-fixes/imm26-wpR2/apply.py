#!/usr/bin/env python3
"""imm26-wpR2: negotiated deals and repair agreements resume after a save/load (Shay 2026-10-15, "everything resumes").

(b) Deal windows (PROPOSED/COUNTERED 10 min, ACCEPTED 2 min, NPC-side dispatch 45 s, truce/protect/pay windows) are wall-clock.
    A reload/restart inside a window silently ended the offer. Now the first negotiation tick of a NEW load pauses the clock:
    shift = min(time since the last tick, 1200 s), per deal capped at 3600 s in total (hard cap). Deals that were already past
    their window at the last tick expire as of then (no resurrection). Per-deal shifts live in stobe_social_contract.resume_shifts,
    pending NPC directives are shifted too. Kill switch STOBE_DEAL_RESUME_ENABLED (env or general setting, default 1).
(a) Repair/restitution agreements pin {campaign, timeline_epoch, native_session_id}; any load made the term IMPOSSIBLE
    (exact_restitution_scope_changed) and demoted VERIFIED terms. Now a LATER load of the SAME campaign (epoch strictly greater, both
    storage ids frozen, game time not rolled back before acceptance) counts as the same scope: proof already banked stays valid,
    open terms stay open and the ticket refresh is re-issued under the new epoch/session. The frozen scope is never rewritten and
    proof evidence is still matched against the original epoch/session (a different campaign, an older epoch or a forged scope is
    rejected). An open term that can no longer be proven after a reload ends IMPOSSIBLE, not UNMET (no promise-broken penalty).
    Kill switch STOBE_REPAIR_RESCOPE_ENABLED (env or general setting, default 1).
Usage (WSL): python3 apply.py <tree-root>   (idempotent; asserts anchors; keeps each file's CRLF/LF mix; installs the regression test)"""
import sys, os, re, shutil

root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))


def load(rel):
    return open(os.path.join(root, rel), encoding='utf-8', newline='').read()


def save(rel, s):
    open(os.path.join(root, rel), 'w', encoding='utf-8', newline='').write(s)


def sub(s, anchor, repl):
    """Replace exactly one occurrence of anchor (LF text, matched against LF or CRLF) with repl, using the matched EOL."""
    pat = re.escape(anchor).replace('\\\n', '\n').replace('\n', '\r?\n')
    ms = list(re.finditer(pat, s))
    assert len(ms) == 1, 'anchor missing/duplicated (%d): %r' % (len(ms), anchor[:90])
    m = ms[0]
    eol = '\r\n' if '\r\n' in m.group(0) else ('\r\n' if s.count('\r\n') > s.count('\n') / 2 else '\n')
    return s[:m.start()] + repl.replace('\n', eol) + s[m.end():]


# ---------------------------------------------------------------- negotiation_engine.php
NEG = 'lib/negotiation_engine.php'
s = load(NEG)
if 'stobeNegDealResumeOnLoad' not in s:
    s = sub(s, "const STOBE_NEG_BETRAYAL_MAX_CHANCE = 0.15;\n",
            "const STOBE_NEG_BETRAYAL_MAX_CHANCE = 0.15;\n"
            "const STOBE_DEAL_RESUME_MAX_GAP_SECONDS = 1200;   // imm26 wpR2: one reload pauses a deal clock by at most 20 min\n"
            "const STOBE_DEAL_RESUME_MAX_TOTAL_SECONDS = 3600; // imm26 wpR2: hard cap on the total pause per deal\n")
    s = sub(s, "        \"ALTER TABLE stobe_social_contract ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMP\",\n",
            "        \"ALTER TABLE stobe_social_contract ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMP\",\n"
            "        \"ALTER TABLE stobe_social_contract ADD COLUMN IF NOT EXISTS resume_shifts JSONB NOT NULL DEFAULT '[]'::jsonb\",\n"
            "        \"ALTER TABLE stobe_social_contract ADD COLUMN IF NOT EXISTS resume_shift_total INT NOT NULL DEFAULT 0\",\n"
            "        \"CREATE TABLE IF NOT EXISTS stobe_deal_clock (id SMALLINT PRIMARY KEY, load_token TEXT NOT NULL DEFAULT '', last_tick_unix BIGINT NOT NULL DEFAULT 0)\",\n")
    helper = r'''// ------------------------------------------------------------------ imm26 wpR2: deals survive a save/load
function stobeDealResumeEnabled(): bool {
    $v = getenv('STOBE_DEAL_RESUME_ENABLED');
    if ($v !== false && $v !== '') return !in_array(strtolower(trim($v)), ['0','false','no','off'], true);
    try { return getSettingBool('STOBE_DEAL_RESUME_ENABLED', true); } catch (Throwable $e) { return true; }
}

/** Identity of the running native load (campaign|epoch|session). Empty when there is no connected campaign. */
function stobeNegDealLoadToken(): string {
    if (isset($GLOBALS['STOBE_DEAL_LOAD_TOKEN_OVERRIDE'])) return strval($GLOBALS['STOBE_DEAL_LOAD_TOKEN_OVERRIDE']); // tests
    try {
        if (!function_exists('stobeSocialScope')) require_once __DIR__ . '/social_runtime.php';
        $scope = stobeSocialScope($GLOBALS['db']);
        return strval($scope['campaign_id'] ?? '') . '|' . strval($scope['timeline_epoch'] ?? '') . '|' . strval($scope['native_session_id'] ?? '');
    } catch (Throwable $e) { return ''; }
}

/** Seconds of reload pause that happened after $sinceUnix (the moment a term was dispatched / the deal started). */
function stobeNegResumeShiftSince(array $deal, int $sinceUnix): int {
    $shifts = stobeNegDecode($deal['resume_shifts'] ?? []);
    $sum = 0;
    foreach ($shifts as $s) {
        if (is_array($s) && intval($s['at_unix'] ?? 0) > $sinceUnix) $sum += max(0, intval($s['seconds'] ?? 0));
    }
    return min($sum, STOBE_DEAL_RESUME_MAX_TOTAL_SECONDS);
}

/**
 * Called at the top of every negotiation tick. The first tick of a NEW load pauses the wall-clock windows of the open deals
 * for the time the server saw no tick (the reload), capped. Returns the pause (seconds) of the largest shift applied.
 */
function stobeNegDealResumeOnLoad(int $now, ?string $token = null): int {
    try {
        $token = $token ?? stobeNegDealLoadToken();
        if ($token === '') return 0;
        $db = $GLOBALS['db'];
        $row = $db->fetchOne("SELECT load_token, last_tick_unix FROM stobe_deal_clock WHERE id=1");
        if (!is_array($row)) {
            $db->exec("INSERT INTO stobe_deal_clock (id, load_token, last_tick_unix) VALUES (1, $1, $2) ON CONFLICT (id) DO NOTHING", [$token, $now]);
            return 0;
        }
        if (strval($row['load_token']) === $token) {
            $db->exec("UPDATE stobe_deal_clock SET last_tick_unix=$1 WHERE id=1 AND load_token=$2 AND last_tick_unix < $1", [$now, $token]);
            return 0;
        }
        // Atomic claim: only the request that flips the token applies the pause.
        $claim = $db->fetchAll(
            "WITH old AS (SELECT last_tick_unix FROM stobe_deal_clock WHERE id=1 FOR UPDATE)
             UPDATE stobe_deal_clock c SET load_token=$1, last_tick_unix=$2 FROM old WHERE c.id=1 AND c.load_token<>$1
             RETURNING old.last_tick_unix AS prev", [$token, $now]);
        if (!is_array($claim) || count($claim) !== 1) return 0;
        $prev = intval($claim[0]['prev'] ?? 0);
        if ($prev <= 0 || $now <= $prev || !stobeDealResumeEnabled()) return 0;
        return stobeNegDealResumeApply($now, $now - $prev, $token);
    } catch (Throwable $e) {
        stobeLogWarn('Deal resume failed (imm26 wpR2)', ['error'=>$e->getMessage()]);
        return 0;
    }
}

function stobeNegDealResumeApply(int $now, int $gap, string $token): int {
    $db = $GLOBALS['db'];
    // A window that had already run out when the last tick happened is not revived by the reload.
    $db->exec("UPDATE stobe_social_contract SET status='EXPIRED', resolved_at=NOW(), updated_at=NOW()
                WHERE status IN ('PROPOSED','COUNTERED') AND updated_at < NOW() - make_interval(secs => $1::double precision) - INTERVAL '10 minutes'", [$gap]);
    $db->exec("UPDATE stobe_social_contract SET status='IMPOSSIBLE', resolved_at=NOW(), updated_at=NOW(),
                evidence = (CASE WHEN jsonb_typeof(evidence)='object' THEN evidence ELSE '{}'::jsonb END) || '{\"note\":\"accepted_but_never_dispatched\"}'::jsonb
                WHERE status='ACCEPTED' AND updated_at < NOW() - make_interval(secs => $1::double precision) - INTERVAL '2 minutes'", [$gap]);
    $perLoad = min($gap, STOBE_DEAL_RESUME_MAX_GAP_SECONDS);
    $rows = $db->fetchAll("SELECT contract_id, status, resume_shifts, resume_shift_total FROM stobe_social_contract
                            WHERE status IN ('PROPOSED','COUNTERED','ACCEPTED','AWAITING_PERFORMANCE') LIMIT 200");
    $applied = 0;
    foreach (is_array($rows) ? $rows : [] as $deal) {
        $total = max(0, intval($deal['resume_shift_total'] ?? 0));
        $shift = min($perLoad, max(0, STOBE_DEAL_RESUME_MAX_TOTAL_SECONDS - $total));
        if ($shift <= 0) continue;
        $shifts = stobeNegDecode($deal['resume_shifts'] ?? []);
        $shifts[] = ['at_unix'=>$now, 'seconds'=>$shift, 'load'=>$token];
        $shifts = array_slice($shifts, -16);
        $id = strval($deal['contract_id']);
        $ok = $db->exec(
            "UPDATE stobe_social_contract SET resume_shifts=$2::jsonb, resume_shift_total=resume_shift_total+$3,
                    updated_at=(CASE WHEN status IN ('PROPOSED','COUNTERED','ACCEPTED') THEN LEAST(updated_at + make_interval(secs => $3::double precision), NOW()) ELSE updated_at END)
              WHERE contract_id=$1 AND status=$4",
            [$id, json_encode($shifts), $shift, strval($deal['status'])]);
        if ($ok === false) continue;
        // A directive that was queued before the reload must still be deliverable after it.
        $db->exec("UPDATE stobe_negotiation_directive SET created_unix=LEAST(created_unix + $2::bigint, $3::bigint) WHERE contract_id=$1 AND consumed_unix=0", [$id, $shift, $now]);
        $applied = max($applied, $shift);
    }
    if ($applied > 0) stobeLogInfo('Deal clocks paused across a load (imm26 wpR2)', ['gap'=>$gap, 'shift'=>$applied]);
    return $applied;
}

'''
    s = sub(s, "/** Run verification for open deals. Cheap when nothing is open; throttled by caller. */\n",
            helper + "/** Run verification for open deals. Cheap when nothing is open; throttled by caller. */\n")
    s = sub(s, "    $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));\n    $now = time();\n    $params = [];\n",
            "    $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));\n    $now = time();\n    stobeNegDealResumeOnLoad($now); // imm26 wpR2: a reload pauses the deal windows\n    $params = [];\n")
    s = sub(s, "        $age = $now - intval($term['dispatched_unix']);\n",
            "        $age = $now - intval($term['dispatched_unix']) - stobeNegResumeShiftSince($deal, intval($term['dispatched_unix'])); // imm26 wpR2\n")
    s = sub(s, "    $deadline = intval($term['deadline_unix'] ?? 0);\n    $gametsDeadline = intval($deal['deadline_gamets'] ?? 0);\n",
            "    $deadline = intval($term['deadline_unix'] ?? 0);\n    $gametsDeadline = intval($deal['deadline_gamets'] ?? 0);\n    $resumeShift = stobeNegResumeShiftSince($deal, $start); // imm26 wpR2: reload pause since this term started\n")
    s = sub(s, "        if ($now - $start >= STOBE_NEG_TRUCE_OBSERVE_SECONDS) {\n",
            "        if ($now - $start - $resumeShift >= STOBE_NEG_TRUCE_OBSERVE_SECONDS) {\n")
    s = sub(s, "        if ($now - $start >= STOBE_NEG_PROTECT_QUIET_SECONDS && count($recent) === 0) {\n",
            "        if ($now - $start - $resumeShift >= STOBE_NEG_PROTECT_QUIET_SECONDS && count($recent) === 0) {\n")
    s = sub(s, "    $expired = ($deadline > 0 && $now > $deadline);\n",
            "    $expired = ($deadline > 0 && $now - $resumeShift > $deadline);\n")
    s = sub(s, "($now > $deadline + STOBE_NEG_PAY_WINDOW_REAL_CAP)",
            "($now - $resumeShift > $deadline + STOBE_NEG_PAY_WINDOW_REAL_CAP)")
    s = sub(s, "        $sinceStart = $now - intval($deal['performance_started_unix'] ?? 0);\n",
            "        $sinceStart = $now - intval($deal['performance_started_unix'] ?? 0) - stobeNegResumeShiftSince($deal, intval($deal['performance_started_unix'] ?? 0)); // imm26 wpR2\n")
    save(NEG, s)
    print('negotiation_engine.php: applied')
else:
    print('negotiation_engine.php: already applied')

# ---------------------------------------------------------------- social_repair_agreements.php
REP = 'lib/social_repair_agreements.php'
s = load(REP)
if 'stobeSocialRepairScopeCurrent' not in s:
    helper = r'''function stobeSocialRepairRescopeEnabled(): bool {
    $v = getenv('STOBE_REPAIR_RESCOPE_ENABLED');
    if ($v !== false && $v !== '') return !in_array(strtolower(trim($v)), ['0','false','no','off'], true);
    try { return getSettingBool('STOBE_REPAIR_RESCOPE_ENABLED', true); } catch (Throwable $e) { return true; }
}

/**
 * imm26 wpR2: is $current (the server-authenticated live scope) the frozen $scope, or a LATER load of the SAME campaign?
 * The frozen scope is never rewritten; evidence is still matched against it. Different campaign, an older/equal epoch,
 * a missing session, a missing frozen storage id, or game time rolled back before acceptance all fail closed.
 */
function stobeSocialRepairScopeCurrent(array $scope,array $current): bool {
    $keys=['campaign_id','timeline_epoch','native_session_id'];$same=true;
    foreach ($keys as $k) if (($scope[$k] ?? null)!==($current[$k] ?? null)) $same=false;
    if ($same) return true;
    if (!stobeSocialRepairRescopeEnabled()) return false;
    $campaign=$scope['campaign_id'] ?? null;
    if (!is_string($campaign) || $campaign==='' || $campaign!==($current['campaign_id'] ?? null)) return false;
    $e0=$scope['timeline_epoch'] ?? null;$e1=$current['timeline_epoch'] ?? null;
    if (!is_string($e0) || !is_string($e1) || !preg_match('/^[0-9]{1,18}$/D',$e0) || !preg_match('/^[0-9]{1,18}$/D',$e1) || intval($e1)<=intval($e0)) return false;
    $session=$current['native_session_id'] ?? null;
    if (!is_string($session) || $session==='') return false;
    foreach (['giver_storage_id','recipient_storage_id'] as $k) if (!is_string($scope[$k] ?? null) || $scope[$k]==='') return false;
    $accepted=intval($scope['acceptance_gamets'] ?? 0);
    if ($accepted>0) {
        try { $game=stobeSocialNowGameTs(); } catch (Throwable $e) { $game=0; }
        if ($game>0 && $game<$accepted) return false;
    }
    return true;
}

'''
    s = sub(s, "/** Pure exact allocation planner. Multiple same-type obligations/grievances/prototypes are ambiguous. */\n",
            helper + "/** Pure exact allocation planner. Multiple same-type obligations/grievances/prototypes are ambiguous. */\n")
    s = sub(s, "        foreach (['campaign_id','timeline_epoch','native_session_id'] as $key) if (($scope[$key] ?? null)!==($current[$key] ?? null)) return $terms;\n",
            "        if (!stobeSocialRepairScopeCurrent($scope,$current)) return $terms; // imm26 wpR2: same campaign, later load\n")
    # ticket refresh: pick every open contract of this pair that continues into the current load, issue under the current epoch/session
    s = sub(s, "        foreach (['campaign_id','timeline_epoch','native_session_id'] as $k) if (($scope[$k] ?? null)!==($current[$k] ?? null)) return;\n",
            "        if (!stobeSocialRepairScopeCurrent($scope,$current)) return; // imm26 wpR2\n")
    s = sub(s, "AND baseline->'repair_binding_scope'->>'campaign_id'=$1 AND baseline->'repair_binding_scope'->>'timeline_epoch'=$2 AND baseline->'repair_binding_scope'->>'native_session_id'=$3 AND baseline->'repair_binding_scope'->>'giver_storage_id'=$4 AND baseline->'repair_binding_scope'->>'recipient_storage_id'=$5\",\n            [$scope['campaign_id'],$scope['timeline_epoch'],$scope['native_session_id'],$scope['giver_storage_id'],$scope['recipient_storage_id']]);\n",
            "AND baseline->'repair_binding_scope'->>'campaign_id'=$1 AND baseline->'repair_binding_scope'->>'giver_storage_id'=$2 AND baseline->'repair_binding_scope'->>'recipient_storage_id'=$3\",\n            [$scope['campaign_id'],$scope['giver_storage_id'],$scope['recipient_storage_id']]); // imm26 wpR2: epoch/session filtered below by stobeSocialRepairScopeCurrent\n")
    s = sub(s, "            $base=stobeNegDecode($row['baseline']);$state=stobeNegDecode($row['term_state']);\n            foreach ($base['repair_action_tickets'] ?? [] as $ticket) {\n",
            "            $base=stobeNegDecode($row['baseline']);$state=stobeNegDecode($row['term_state']);\n            if (!stobeSocialRepairScopeCurrent(is_array($base['repair_binding_scope'] ?? null) ? $base['repair_binding_scope'] : [],$current)) continue;\n            foreach ($base['repair_action_tickets'] ?? [] as $ticket) {\n")
    s = sub(s, "if (($term['status'] ?? '')==='AWAITING_PLAYER' && $ticket['deadline_gamets']>=stobeSocialNowGameTs()) $tickets[]=$ticket;\n",
            "if (($term['status'] ?? '')==='AWAITING_PLAYER' && $ticket['deadline_gamets']>=stobeSocialNowGameTs()) $tickets[]=['timeline_epoch'=>$current['timeline_epoch'],'native_session_id'=>$current['native_session_id']]+$ticket;\n")
    s = sub(s, "        $envelope=['schema_version'=>1,'campaign_id'=>$scope['campaign_id'],'timeline_epoch'=>$scope['timeline_epoch'],\n            'native_session_id'=>$scope['native_session_id'],",
            "        $envelope=['schema_version'=>1,'campaign_id'=>$scope['campaign_id'],'timeline_epoch'=>$current['timeline_epoch'],\n            'native_session_id'=>$current['native_session_id'],")
    s = sub(s, "        foreach (['campaign_id','timeline_epoch','native_session_id'] as $k) if (($event[$k] ?? null)!==$ticket[$k]) return null;\n",
            "        if (!stobeSocialRepairScopeCurrent($ticket,$current)) return null; // imm26 wpR2: event==current was checked above\n")
    s = sub(s, "foreach (['campaign_id','timeline_epoch','native_session_id'] as $k) if ($current[$k]!==$scope[$k]) {\n        $term['status']='IMPOSSIBLE';$term['evidence'][]=['at'=>$now,'note'=>'exact_restitution_scope_changed'];return $term;\n    }\n",
            "$rescoped=false;foreach (['campaign_id','timeline_epoch','native_session_id'] as $k) if (($current[$k] ?? null)!==($scope[$k] ?? null)) $rescoped=true;\n"
            "    if ($rescoped && !stobeSocialRepairScopeCurrent($scope,$current)) {\n        $term['status']='IMPOSSIBLE';$term['evidence'][]=['at'=>$now,'note'=>'exact_restitution_scope_changed'];return $term;\n    }\n")
    s = sub(s, "        $term['status']='UNMET';$term['evidence'][]=['at'=>$now,'note'=>'exact_receipt_deadline_passed'];\n",
            "        // imm26 wpR2: after a reload the item identity cannot be proven (load-local keys); that is not a broken promise.\n"
            "        if ($rescoped) {$term['status']='IMPOSSIBLE';$term['evidence'][]=['at'=>$now,'note'=>'exact_restitution_unprovable_after_reload'];}\n"
            "        else {$term['status']='UNMET';$term['evidence'][]=['at'=>$now,'note'=>'exact_receipt_deadline_passed'];}\n")
    s = sub(s, "        $same=true;\n        foreach(['campaign_id','timeline_epoch','native_session_id'] as $k)if(($scope[$k] ?? null)!==($current[$k] ?? null))$same=false;\n",
            "        $same=stobeSocialRepairScopeCurrent($scope,$current); // imm26 wpR2: banked proof survives a later load of the same campaign\n")
    save(REP, s)
    print('social_repair_agreements.php: applied')
else:
    print('social_repair_agreements.php: already applied')

shutil.copy(os.path.join(here, 'imm26_wpR2_resume_regression.php'), os.path.join(root, 'tests', 'imm26_wpR2_resume_regression.php'))
print('regression test installed')
