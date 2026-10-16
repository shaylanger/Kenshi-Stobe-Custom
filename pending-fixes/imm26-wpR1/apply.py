#!/usr/bin/env python3
"""imm26-wpR1: Hunt / Mine / ClearGroup (+ camp zone) activities and pending offers survive a save/load (Shay 2026-10-15,
memory everything-resumes-after-save-load; audit gap 1). SERVER ONLY, kill switch STOBE_ACTIVITY_RESUME_ENABLED (default 1).
Problem: the record is keyed by the native load epoch (world_id); a load builds a new epoch, native Reset cancels the goal and revokes every
grant for good, and nothing on the server looked at records of an older epoch (record 'accepted' forever, NPC stops silently).
Changes (CRLF-preserving, anchored, idempotent):
  lib/activity/ActivityResume.php   NEW  settings (env/getSetting: ENABLED, MAX_COUNT 3, MAX_AGE_GAMETS 7200, ROUTE_RADIUS 1500),
                                         verdict (rollback / expiry / cap / too old / legacy), sweep (poll), chat resume (re-ground + re-grant)
  lib/activity/ActivityAgreementAdapter.php  + resume(): same terms re-grounded to the NEW epoch; accepted -> NEW agreement id + grant envelope
  lib/activity/ActivityStore.php    + staleActive / activeForActor / endStale / commitResume
  lib/activity/ActivityLifecycle.php + reason 'interrupted_by_load'
  lib/activity/ActivityChat.php     resume attempt at chat begin when this epoch has no record for the pair
  activity.php                      poll: sweep older epochs first; history rows for jobs the sweep ended
  tests/imm26_wpR1_activity_resume_regression.php, tests/imm26_wpR1_area_goal_resume_regression.php
Why a NEW agreement id for an accepted job: ActivityRuntimeBindings.cpp:57-59 marks every grant revoked on a new epoch and :110-113 rejects a
revoked / mutated id ("revoked_replayed_or_mutated_grant"), so the old id can never be granted again with the installed DLL.
Usage (WSL): python3 apply.py <tree-root>"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))

def load(p):
    s = open(p, encoding='utf-8', newline='').read()
    crlf = '\r\n' in s
    return (s.replace('\r\n', '\n') if crlf else s), crlf
def save(p, s, crlf):
    open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', '\r\n') if crlf else s)
def edit(rel, marker, pairs):
    p = os.path.join(root, rel)
    s, crlf = load(p)
    if marker in s:
        print(rel + ': already applied'); return
    for a, b in pairs:
        assert s.count(a) == 1, rel + ': anchor missing/duplicated: ' + a[:80]
        s = s.replace(a, b)
    save(p, s, crlf)
    print(rel + ': patched')

# ---------------------------------------------------------------- adapter
edit('lib/activity/ActivityAgreementAdapter.php', 'public function resume(', [(
"""    /** Explicit cancellation requires authenticated requester/NPC withdrawal. */
""",
"""    /**
     * Save/load continuation (imm26-wpR1). The agreed terms are re-grounded against the NEW native epoch: $reference and $routeSelector
     * come from the fresh native facts of this request. A PROPOSED offer keeps its id; an ACCEPTED job continues as $newId because the
     * native side revokes every grant of the old epoch for good. No new consent is taken: the original consent stands (acceptedAt kept),
     * the original deadline stands (expiresAt / proposalExpiresAt are never extended). Throws when anything no longer grounds.
     */
    public function resume(array $context, array $record, array $reference, array $routeSelector, string $newId): array
    {
        $this->context($context);
        $status = $record['status'] ?? '';
        if (!in_array($status, ['proposed', 'accepted'], true) || ($record['protocol'] ?? '') !== 'stobe.activity.v2' ||
            !isset($record['agreement'], $record['discoveryRef'], $record['routeRef'], $record['createdAt'], $record['lastNow'],
                   $record['proposalExpiresAt'], $record['revision'], $record['scopeDigest'])) {
            throw new \\RuntimeException('Invalid persisted agreement state');
        }
        $agreement = $record['agreement'];
        foreach (['actor', 'requester'] as $field) {
            if (($agreement[$field] ?? null) !== $context[$field]) { throw new \\RuntimeException('Agreement identity mismatch'); }
        }
        $deadline = $status === 'proposed' ? $record['proposalExpiresAt'] : ($agreement['expiresAt'] ?? 0);
        if (!hash_equals($this->digest($record), $record['scopeDigest']) || $context['now'] < $record['lastNow'] || $context['now'] >= $deadline) {
            throw new \\RuntimeException('Agreement changed, expired, or belongs to an earlier timeline');
        }
        $this->keys($reference, ['candidateId', 'targetSerial']);
        $reference = ['candidateId' => $this->identifier($reference['candidateId'] ?? null),
                      'targetSerial' => $this->integer($reference['targetSerial'] ?? null, 1, 4294967295)];
        $this->keys($routeSelector, ['candidateId']);
        $routeRef = $this->resolveRoute($context, $this->identifier($routeSelector['candidateId'] ?? null), null);
        $agreement['worldId'] = $context['worldId'];
        if ($status === 'accepted') {
            if (!preg_match('/\\Aactivity-[a-f0-9]{32}\\z/D', $newId)) { throw new \\InvalidArgumentException('Invalid continuation id'); }
            $agreement['id'] = $newId;
        }
        $this->ground($context, $agreement, $reference);
        $this->resolveRoute($context, $routeRef['candidateId'], $routeRef);
        $this->authorize('accept', $context, $agreement);
        $resumed = $record;
        $resumed['agreement'] = $agreement;
        $resumed['discoveryRef'] = $reference;
        $resumed['routeRef'] = $routeRef;
        $resumed['lastNow'] = $context['now'];
        $resumed['revision'] = $status === 'accepted' ? 2 : $record['revision'] + 1;
        $resumed['scopeDigest'] = $this->digest($resumed);
        $envelope = null;
        if ($status === 'accepted') {
            $envelope = ['protocol' => $resumed['protocol'], 'operation' => 'grant',
                         'agreement' => $resumed['agreement'], 'discoveryRef' => $resumed['discoveryRef'],
                         'scopeDigest' => $resumed['scopeDigest'], 'revision' => $resumed['revision'], 'routeRef' => $resumed['routeRef']];
            if (function_exists('stobeActivityHandbackEnabled') && stobeActivityHandbackEnabled()
                && !empty(stobeActivityKindInfo((string)$resumed['agreement']['kind'])['handback'])) { $envelope['handback'] = true; }
        }
        return ['record' => $resumed, 'envelope' => $envelope];
    }

    /** Explicit cancellation requires authenticated requester/NPC withdrawal. */
""")])

# ---------------------------------------------------------------- store
edit('lib/activity/ActivityStore.php', 'function staleActive(', [(
"""    public function active(string $world): array {""",
"""    /** Active records of OTHER native epochs (a save/load left them behind); $actor + $requester narrow it to one pair. */
    public function staleActive(string $world, ?int $actor = null, ?int $requester = null): array {
        $sql = "SELECT record FROM stobe_activity_record WHERE world_id<>$1 AND record->>'status' IN ('proposed','accepted')";
        $args = [$world];
        if ($actor !== null) { $sql .= ' AND actor=$2 AND requester=$3'; $args[] = $actor; $args[] = $requester; }
        $result = $this->run($sql . ' ORDER BY actor,id FOR UPDATE', $args);
        $out = []; while ($row = $this->db->fetchArray($result)) $out[] = json_decode($row['record'], true, 512, JSON_THROW_ON_ERROR);
        return $out;
    }
    /** The proposed/accepted record of this epoch for the actor, if any. */
    public function activeForActor(string $world, int $actor): ?array {
        $result = $this->run("SELECT record FROM stobe_activity_record WHERE world_id=$1 AND actor=$2 AND record->>'status' IN ('proposed','accepted') FOR UPDATE", [$world, $actor]);
        $row = $this->db->fetchArray($result);
        return $row ? json_decode($row['record'], true, 512, JSON_THROW_ON_ERROR) : null;
    }
    /** Store a stale record's new state (ended, or marked pending) by compare-and-swap on its revision. */
    public function endStale(array $record, int $expectedRevision): void {
        $updated = $this->run('UPDATE stobe_activity_record SET revision=$1,record=$2::jsonb WHERE id=$3 AND revision=$4',
            [$record['revision'], json_encode($record, JSON_THROW_ON_ERROR), $record['agreement']['id'], $expectedRevision]);
        if ($this->db->affectedRows($updated) !== 1) throw new \\RuntimeException('Concurrent agreement change');
    }
    /**
     * Move an interrupted job to the current epoch. $ended = the old record already marked superseded (an ACCEPTED job continues under a
     * NEW id with a grant in the outbox); null = a PROPOSED offer keeps its id and its row moves to the new world.
     */
    public function commitResume(?array $ended, int $expectedRevision, array $resumed, ?array $envelope, string $nonce): void {
        $a = $resumed['agreement'];
        if ($ended === null) {
            $updated = $this->run('UPDATE stobe_activity_record SET world_id=$1,revision=$2,record=$3::jsonb WHERE id=$4 AND revision=$5',
                [$a['worldId'], $resumed['revision'], json_encode($resumed, JSON_THROW_ON_ERROR), $a['id'], $expectedRevision]);
            if ($this->db->affectedRows($updated) !== 1) throw new \\RuntimeException('Concurrent agreement change');
            return;
        }
        $this->endStale($ended, $expectedRevision);
        $this->run('INSERT INTO stobe_activity_record(id,world_id,actor,requester,revision,record) VALUES($1,$2,$3,$4,$5,$6::jsonb)',
            [$a['id'], $a['worldId'], $a['actor'], $a['requester'], $resumed['revision'], json_encode($resumed, JSON_THROW_ON_ERROR)]);
        if ($envelope !== null) {
            $envelope['nonce'] = $nonce;
            $this->run('INSERT INTO stobe_activity_outbox(world_id,actor,agreement_id,revision,envelope) VALUES($1,$2,$3,$4,$5::jsonb)',
                [$a['worldId'], $a['actor'], $a['id'], $resumed['revision'], json_encode($envelope, JSON_THROW_ON_ERROR)]);
        }
    }
    public function active(string $world): array {""")])

# ---------------------------------------------------------------- lifecycle reason
edit('lib/activity/ActivityLifecycle.php', "'interrupted_by_load'", [(
"""        'inventory_full'       => 'there was no room left to carry the result',
""",
"""        'inventory_full'       => 'there was no room left to carry the result',
        'interrupted_by_load'  => 'a save and load interrupted the job and it could not be picked up again',
""")])

# ---------------------------------------------------------------- chat
edit('lib/activity/ActivityChat.php', 'stobeActivityResumeForChat', [(
"""require_once __DIR__.'/ActivityLifecycle.php';
""",
"""require_once __DIR__.'/ActivityLifecycle.php';
require_once __DIR__.'/ActivityResume.php';
"""), (
"""    stobeActivityAppendDynamicTail($messages,['offer'=>$record,""",
"""    // imm26-wpR1: this epoch has no record for the pair, but an older epoch may (a save/load interrupted the job or the offer).
    if ($record === null) {
        try {
            $resumeEnded = [];
            $record = $store->transaction(static fn() => stobeActivityResumeForChat($store,$request,$resumeEnded));
            foreach ($resumeEnded as $endedRecord) { try { stobeActivityRecordHistory($endedRecord); } catch (Throwable $historyError) { /* informational */ } }
        } catch (Throwable $resumeError) {
            $record = null;
            if (function_exists('stobeLogWarn')) stobeLogWarn('Activity resume failed safely',['error'=>$resumeError->getMessage()]);
        }
    }
    stobeActivityAppendDynamicTail($messages,['offer'=>$record,""")])

# ---------------------------------------------------------------- endpoint
edit('activity.php', 'stobeActivityResumeSweep', [(
"""    require_once __DIR__ . '/lib/relationship_participation.php';
""",
"""    require_once __DIR__ . '/lib/relationship_participation.php';
    require_once __DIR__ . '/lib/activity/ActivityResume.php';
"""), (
"""    $eventToRecord = null;
""",
"""    $eventToRecord = null;
    $resumeEnded = [];
"""), (
"""use ($store,$adapter,$request,$context,$nonce,&$eventToRecord): array {""",
"""use ($store,$adapter,$request,$context,$nonce,&$eventToRecord,&$resumeEnded): array {"""), (
"""            foreach ($store->active($context['worldId']) as $active) {""",
"""            // imm26-wpR1: records an older native epoch left behind (save/load) are ended or marked pending before anything else.
            stobeActivityResumeSweep($store,$context,$resumeEnded);
            foreach ($store->active($context['worldId']) as $active) {"""), (
"""    if (($request['operation'] ?? '') === 'event' && is_array($eventToRecord)) {""",
"""    foreach ($resumeEnded as $endedRecord) {
        try { stobeActivityRecordHistory($endedRecord); } catch (Throwable $optionalHistoryError) { /* History is informational. */ }
    }
    if (($request['operation'] ?? '') === 'event' && is_array($eventToRecord)) {""")])

# ---------------------------------------------------------------- new files
dst = os.path.join(root, 'lib', 'activity', 'ActivityResume.php')
src = os.path.join(here, 'ActivityResume.php')
sb = open(src, 'rb').read()
if not os.path.exists(dst) or open(dst, 'rb').read() != sb:
    shutil.copy(src, dst); print('ActivityResume.php installed')
for t in ('imm26_wpR1_activity_resume_regression.php', 'imm26_wpR1_area_goal_resume_regression.php'):
    shutil.copy(os.path.join(here, t), os.path.join(root, 'tests', t))
print('applied')
