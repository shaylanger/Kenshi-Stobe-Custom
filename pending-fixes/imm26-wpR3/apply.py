#!/usr/bin/env python3
"""imm26-wpR3: open social windows survive a save/load (audit gap 5, memory everything-resumes-after-save-load).
Before: pending-awareness / care / carry / food-gift / injury-episode / theft-hunt incidents live in social_incident rows scoped to
timeline_epoch = the load id, and their entity keys are 'session:epoch:serial' (load-local), so the next load never saw them.
Now: on the FIRST structured captured event of a new load (same campaign = same save lineage) SocialStore::resumeWindows() re-binds the
still-open incidents of earlier loads into the new epoch:
  - same campaign, game_ts inside [now - window, now] (a load of an OLDER time skips newer rows: they are not resumed),
  - entity keys rewritten to the new load's prefix (state JSON, 'parties'/'pending' map keys, 'a|b' pair keys), food ids recomputed,
  - game_ts and the whole state kept, so the REMAINING window time and effect rules are unchanged,
  - newest copy per incident id wins (chains of loads never double up), hard cap per load (default 64, setting
    STOBE_SOCIAL_WINDOW_RESUME_MAX, clamped 1..128), checkpointed (a rollback keeps the copies),
  - kill switch STOBE_SOCIAL_WINDOW_RESUME_ENABLED (default true; false/0/no = old behaviour),
  - a 'resume:marker' incident per load makes it run once; failures are contained in a savepoint (ingest never fails because of it).
KO incidents keep their own older carry-over (activeKo/retireIncident) and are excluded here; theft/social_repair have theirs.
Usage (WSL): python3 apply.py <tree-root>     (idempotent; asserts anchors; keeps CRLF; installs the regression test)"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(root, 'lib', 'social_store.php')
s = open(p, encoding='utf-8', newline='').read()
CRLF = '\r\n' in s
if CRLF: s = s.replace('\r\n', '\n')
if 'resumeWindows' in s:
    print('already applied'); sys.exit(0)
A1 = ("            if (($event['facts']['source'] ?? null) !== 'structured') return ['status'=>'captured','effects'=>[]];\n"
      "            require_once __DIR__ . '/social_interpreter.php';\n")
A2 = "    /** A KO incident carried into a newer load is closed in its old load (no double resolution). */\n"
for a in (A1, A2):
    assert s.count(a) == 1, 'anchor missing/duplicated: ' + a[:70]
hook = "            $this->resumeWindowsContained($event); // imm26 wpR3: open windows of earlier loads follow into this load\n"
l1, l2 = A1.split('\n')[0] + '\n', A1.split('\n')[1] + '\n'
s = s.replace(A1, l1 + hook + l2)
methods = r'''    /** imm26 wpR3: never lets the resume break an ingest (own savepoint; any failure is logged and skipped). */
    private function resumeWindowsContained(array $event): void
    {
        try {
            $r = $this->transaction(fn() => $this->resumeWindows($event));
            if (!empty($r['resumed']) && function_exists('stobeLogRelationshipInfo')) stobeLogRelationshipInfo('SOCIAL_RESUME', $r + ['campaign'=>$event['campaign_id'], 'epoch'=>$event['timeline_epoch']]);
        } catch (Throwable $e) {
            if (function_exists('stobeLogRelationshipInfo')) stobeLogRelationshipInfo('SOCIAL_RESUME_FAILED', ['error'=>substr($e->getMessage(), 0, 200)]);
        }
    }

    /**
     * imm26 wpR3 (audit gap 5): open social windows follow the campaign across loads. Runs once per load (marker incident),
     * inside ingest's transaction, before the event is interpreted. Rules: header of pending-fixes/imm26-wpR3/apply.py.
     */
    public function resumeWindows(array $event): array
    {
        if (!getSettingBool('STOBE_SOCIAL_WINDOW_RESUME_ENABLED', true)) return ['skipped'=>'disabled'];
        $campaign = $event['campaign_id']; $epoch = $event['timeline_epoch']; $now = (int)$event['game_ts'];
        if ($this->row('SELECT 1 AS x FROM social_incident WHERE campaign_id=$1 AND timeline_epoch=$2 AND incident_id=$3', [$campaign, $epoch, 'resume:marker'])) return ['skipped'=>'done'];
        $newKey = $event['actor']['entity_key'] ?? ($event['target']['entity_key'] ?? null);
        if (!is_string($newKey) || !preg_match('/^(.*:)\d+$/D', $newKey, $m)) return ['skipped'=>'no_entity']; // wait for an event that names someone
        $newPrefix = $m[1];
        $cap = max(1, min(128, getSettingInt('STOBE_SOCIAL_WINDOW_RESUME_MAX', 64)));
        $care = $this->rules->section('care');
        $window = max(86400, (int)($care['own_harm_window_seconds'] ?? 0), (int)($care['food_gift_window_seconds'] ?? 0), (int)($care['carry_window_seconds'] ?? 0));
        $rows = pg_fetch_all($this->query("SELECT timeline_epoch,incident_id,state,game_ts,last_sequence FROM social_incident
            WHERE campaign_id=\$1 AND timeline_epoch<>\$2 AND game_ts<=\$3 AND game_ts>=\$4
              AND COALESCE(state->>'kind','') NOT IN ('ko','social_repair','theft','resume_marker')
              AND (state->>'kind' IN ('combat','carry','food','theft_hunt','escape') OR state->>'phase'='pending_awareness')
            ORDER BY game_ts DESC, length(timeline_epoch) DESC, timeline_epoch DESC LIMIT 400", [$campaign, $epoch, $now, $now - $window])) ?: [];
        $open = ['pending_awareness', 'active', 'carrying', 'dropped', 'open', 'freed'];
        $seen = []; $copied = 0; $skipped = 0;
        foreach ($rows as $row) {
            $state = json_decode($row['state'], true);
            if (!is_array($state)) continue;
            $text = json_encode($state, JSON_THROW_ON_ERROR);
            if (preg_match_all('/"entity_key":"([^"]+:)\d+"/', $text, $keys)) {
                foreach (array_unique($keys[1]) as $old) {
                    if ($old === $newPrefix) continue;
                    $text = str_replace(['"' . $old, '|' . $old], ['"' . $newPrefix, '|' . $newPrefix], $text);
                }
                $state = json_decode($text, true);
            }
            $id = $row['incident_id'];
            if (($state['kind'] ?? '') === 'food' && isset($state['recipient']['entity_key'])) $id = 'food:' . substr(hash('sha256', $state['recipient']['entity_key']), 0, 24);
            if (isset($seen[$id])) continue;          // newest copy per incident wins (chains of loads, rollbacks)
            $seen[$id] = true;
            $phase = (string)($state['phase'] ?? '');
            $isOpen = ($state['kind'] ?? '') === 'combat' ? $phase !== 'carried_over' : in_array($phase, $open, true);
            if (!$isOpen) continue;
            if ($copied >= $cap) { ++$skipped; continue; }
            if ($this->row('SELECT 1 AS x FROM social_incident WHERE campaign_id=$1 AND timeline_epoch=$2 AND incident_id=$3', [$campaign, $epoch, $id])) continue;
            $state['resumed_from'] = ['epoch'=>$row['timeline_epoch'], 'incident'=>$row['incident_id']];
            $this->query('INSERT INTO social_incident(campaign_id,timeline_epoch,incident_id,state,game_ts,last_sequence) VALUES($1,$2,$3,$4::jsonb,$5,0) ON CONFLICT DO NOTHING',
                [$campaign, $epoch, $id, self::json($state), (int)$row['game_ts']]);
            $this->checkpoint($event, $id);
            ++$copied;
        }
        $this->query('INSERT INTO social_incident(campaign_id,timeline_epoch,incident_id,state,game_ts,last_sequence) VALUES($1,$2,$3,$4::jsonb,$5,0) ON CONFLICT DO NOTHING',
            [$campaign, $epoch, 'resume:marker', self::json(['kind'=>'resume_marker', 'phase'=>'closed', 'resumed'=>$copied, 'over_cap'=>$skipped]), $now]);
        return ['resumed'=>$copied, 'over_cap'=>$skipped, 'scanned'=>count($rows)];
    }

'''
s = s.replace(A2, methods + A2)
open(p, 'w', encoding='utf-8', newline='').write(s.replace('\n', '\r\n') if CRLF else s)
shutil.copy(os.path.join(here, 'imm26_wpR3_social_window_resume_regression.php'), os.path.join(root, 'tests', 'imm26_wpR3_social_window_resume_regression.php'))
print('applied')
