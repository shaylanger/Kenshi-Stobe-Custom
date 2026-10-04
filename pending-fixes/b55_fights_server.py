#!/usr/bin/env python3
"""B 55 (Shay 2026-10-03, STOBE_full_test_plan.md section E items 1-8): fights and relationships, server side.

Usage: python3 b55_fights_server.py <StobeServer tree root>
Idempotent anchor patch (asserts every anchor once; skips a hunk whose marker is already present):
- lib/social_fights.php (new, from pending-fixes/b55_social_fights.php)
- social_runtime: stobeSocialIngestMode() (fights mode while SOCIAL_RELATIONSHIP_MODE is off and SOCIAL_FIGHTS_LIVE)
- social_event.php ingests in that mode
- SocialStore: fights mode, fight ranges x closeness, open-grudge half rate, >80 deltas in steps, grudge fade
- SocialRules::calculate: range override, scale/closeness, fixed_total, grudge_rate, unscaled total
- SocialInterpreter: fights-that-matter filter, sparring, accidents, bleeding out on waking, witnesses in fights mode
- social_care aid: the attacker's treatment takes 15-30 % off the fight penalty
- social_agreements: fights mode + deal forgiveness
- social_dialogue: 1 game day chat cooldown + half rate while a fight grudge is open
- chat_helper: R4 retired while REL scores fights, fight memory line in the stance block, spar consent hook
- rules JSON: fights section, treated_relief / deal_forgiveness
- tools/social_relationship_inspect.php: --add-spar, more switches, ingest mode in the summary
- tests: R4 block and property suite legacy check run with SOCIAL_FIGHTS_LIVE=false
"""
import json
import os
import shutil
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '/var/www/html/StobeServer'
HERE = os.path.dirname(os.path.abspath(__file__))


def patch(rel, old, new, marker):
    path = os.path.join(ROOT, rel)
    with open(path, encoding='utf-8') as f:
        text = f.read()
    if marker in text:
        print(f'skip  {rel}: {marker[:60]}')
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'ANCHOR {rel}: found {n}x: {old[:120]!r}')
    text = text.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)
    print(f'patch {rel}: {marker[:60]}')


# ---- new files: lib + regression suite ----
shutil.copyfile(os.path.join(HERE, 'b55_social_fights.php'), os.path.join(ROOT, 'lib/social_fights.php'))
shutil.copyfile(os.path.join(HERE, 'b55_social_fights_regression.php'), os.path.join(ROOT, 'tests/social_fights_regression.php'))
wrapper = os.path.join(ROOT, 'tests/social_relationship/ingame/rel-b55.sh')
shutil.copyfile(os.path.join(HERE, 'rel-b55.sh'), wrapper)
os.chmod(wrapper, 0o755)
print('write lib/social_fights.php, tests/social_fights_regression.php, tests/social_relationship/ingame/rel-b55.sh')
patch('tests/social_relationship/ingame/RUN_ORDER.md',
      "| R4 (item 55) | `RELATIONSHIP_FIGHTS_COUNT` | unchanged; R4 runs in `off`/`shadow`, REL replaces it only in `enabled` | - |",
      "| B 55 fights mode | `SOCIAL_FIGHTS_LIVE` (unset = on) | with the mode `off`, REL runs in \"fights\" mode: fights and deal outcomes change relationships (B 55 rules), everything else is recorded only; R4 is retired. `false` = old behaviour (R4, `RELATIONSHIP_FIGHTS_COUNT`) | delete the row |\n"
      "| B 55 rules / fade | `SOCIAL_FIGHT_RULES` (`rel` = plain phase-8 REL), `SOCIAL_GRUDGE_FADE_DAYS` (14), `SOCIAL_GRUDGE_FADE_THRESHOLD` (30) | `--set-switch <id> <value>` | `--set-switch <id> off` |\n"
      "| B 55 in-game rows | `rel-b55.sh <outdir> [blocks]` | see its header | - |",
      '| B 55 fights mode |')

# ---- runtime ----
patch('lib/social_runtime.php',
      "/** Campaign id used when Playthrough Saves",
      """/**
 * B 55: the mode social capture runs in. SOCIAL_RELATIONSHIP_MODE when shadow/enabled; while it is off, "fights"
 * (only fights and deal outcomes change relationships, see lib/social_fights.php) unless SOCIAL_FIGHTS_LIVE=false.
 */
function stobeSocialIngestMode(): string
{
    $mode = stobeSocialMode();
    if ($mode !== 'off') return $mode;
    try { return getSettingBool('SOCIAL_FIGHTS_LIVE', true) ? 'fights' : 'off'; } catch (Throwable $e) { return 'off'; }
}

/** Campaign id used when Playthrough Saves""",
      'function stobeSocialIngestMode')
patch('lib/social_runtime.php',
      "require_once __DIR__ . '/social_store.php';\n",
      "require_once __DIR__ . '/social_store.php';\nrequire_once __DIR__ . '/social_fights.php'; // B 55\n",
      "social_fights.php'; // B 55")

patch('social_event.php',
      "    $mode = stobeSocialMode();\n",
      "    $mode = stobeSocialIngestMode(); // B 55: 'fights' while SOCIAL_RELATIONSHIP_MODE is off\n",
      'stobeSocialIngestMode(); // B 55')

# ---- store ----
S = 'lib/social_store.php'
patch(S, "require_once __DIR__ . '/social_rules.php';\n",
      "require_once __DIR__ . '/social_rules.php';\nrequire_once __DIR__ . '/social_fights.php'; // B 55\n",
      "social_fights.php'; // B 55")
patch(S, "        if (!in_array($mode, ['shadow', 'enabled'], true)) throw new InvalidArgumentException('Unknown social mode');",
      "        if (!in_array($mode, ['shadow', 'enabled', 'fights'], true)) throw new InvalidArgumentException('Unknown social mode');",
      "['shadow', 'enabled', 'fights'], true)) throw")
patch(S, "            $effects = (new SocialInterpreter($this, $this->rules))->interpret($event, $mode);\n",
      "            $effects = (new SocialInterpreter($this, $this->rules))->interpret($event, $mode);\n"
      "            $effects = array_merge($effects, $this->fadeGrudges($event, $mode)); // B 55 item 1\n",
      '$this->fadeGrudges($event, $mode)')
patch(S, "        if (!in_array($mode,['shadow','enabled'],true)) return ['status'=>'disabled'];",
      "        if (!in_array($mode,['shadow','enabled','fights'],true)) return ['status'=>'disabled'];",
      "['shadow','enabled','fights'],true)) return ['status'=>'disabled']")
patch(S, "            $effect = $this->rules->calculate($incident,$observer,$component,$belief,$context);\n",
      """            if (stobeSocialFightRulesOn()) {
                // B 55 item 7: harsher fight ranges x the victim's closeness to the attacker before this fight.
                $fightRanges = $this->rules->section('fights')['ranges'] ?? [];
                if (isset($fightRanges[$component]) && !isset($context['range'])) $context['range'] = $fightRanges[$component];
                if (in_array($component, STOBE_SOCIAL_CLOSENESS_SCALED, true)) {
                    $spent = $this->row('SELECT COALESCE(SUM(delta),0) AS s FROM social_effect WHERE campaign_id=$1 AND timeline_epoch=$2 AND incident_id=$3 AND observer_key=$4 AND culprit_key=$5 AND applied', array_slice($key, 0, 5));
                    $context['pre_fight_affinity'] = max(-100, min(100, $context['affinity'] - (int)($spent['s'] ?? 0)));
                    $context['closeness'] = stobeSocialClosenessMultiplier($context['pre_fight_affinity'], $this->rules);
                }
                // B 55 item 6: while a fight grudge toward the culprit is open, positive gains count at half rate.
                if ($this->rules->positive($component) && !str_starts_with($component, 'witness_') && !in_array($component, STOBE_SOCIAL_FIGHT_RELIEF, true)
                    && !isset($context['fixed_total']) && stobeSocialGrudgeOutstanding($a['name'], $b['name']) < 0) {
                    $context['grudge_rate'] = (float)($this->rules->section('fights')['grudge_positive_rate'] ?? 0.5);
                }
            }
            $effect = $this->rules->calculate($incident,$observer,$component,$belief,$context);
            foreach (['pre_fight_affinity', 'fight_incident', 'level'] as $k) if (isset($context[$k])) $effect[$k] = $context[$k]; // B 55
""",
      'B 55 item 7: harsher fight ranges')
patch(S, """            $applied = $mode === 'enabled';
            if ($applied && $effect['delta'] !== 0) {
                $updates = stobeApplyRelationshipUpdatesMap($map,[['target'=>$b['name'],'aff_delta'=>$effect['delta'],'note'=>strval($belief['note'] ?? $component)]]);
                if (($updates['updated'] ?? 0) !== 1) throw new RuntimeException('Canonical relationship update refused');
""",
      """            // B 55: fights mode applies only fights and deal outcomes; the rest is recorded as in shadow.
            $applied = $mode === 'enabled' || ($mode === 'fights' && stobeSocialAppliesInFights($this->rules, $component));
            if ($applied && $effect['delta'] !== 0) {
                // The map update caps one change at 80 (B 55 closeness can charge up to 100): apply it in steps.
                $updates = ['map'=>$map]; $remaining = (int)$effect['delta'];
                while ($remaining !== 0) {
                    $step = max(-80, min(80, $remaining)); $remaining -= $step;
                    $updates = stobeApplyRelationshipUpdatesMap($updates['map'],[['target'=>$b['name'],'aff_delta'=>$step,'note'=>strval($belief['note'] ?? $component)]]);
                    if (($updates['updated'] ?? 0) !== 1) throw new RuntimeException('Canonical relationship update refused');
                }
""",
      'B 55: fights mode applies only fights')
patch(S, "        if (!in_array($mode, ['shadow', 'enabled'], true)) return null;\n        return $this->transaction(function () use ($scope, $mode, $eventId",
      "        if (!in_array($mode, ['shadow', 'enabled', 'fights'], true)) return null;\n        return $this->transaction(function () use ($scope, $mode, $eventId",
      "['shadow', 'enabled', 'fights'], true)) return null;")
patch(S, "    // Interpreter helpers (server-owned; never reachable from client input directly).\n",
      r'''    /**
     * B 55 item 1: forgiveness over time, event-based. Each fight incident (per observer -> culprit) is its own grudge;
     * one with no knockout or worse and an unscaled worst charge of at most SOCIAL_GRUDGE_FADE_THRESHOLD fades back
     * linearly over SOCIAL_GRUDGE_FADE_DAYS game days (what treatment/deals already won back is not faded twice).
     * Runs inside ingest at most every fights.fade_check_seconds of game time per load (and after a time jump back).
     * Each step is its own grudge_fade row at the event's game time, so a rollback removes exactly the later steps.
     */
    public function fadeGrudges(array $event, string $mode): array
    {
        if (!in_array($mode, ['enabled', 'fights'], true) || !stobeSocialFightRulesOn() || !getSettingBool('SOCIAL_CATEGORY_COMBAT', true)) return [];
        $ts = (int)$event['game_ts'];
        $every = max(1, (int)($this->rules->section('fights')['fade_check_seconds'] ?? 600));
        $throttle = 'STOBE_REL_FADE_' . md5($event['campaign_id'] . '|' . $event['timeline_epoch']);
        $last = getConfOpt($throttle, '');
        if ($last !== '' && $ts >= (int)$last && $ts - (int)$last < $every) return [];
        setConfOpt($throttle, strval($ts));
        [$threshold, $days] = stobeSocialFadeSettings($this->rules);
        $span = max(1.0, $days * 86400.0);
        $fight = stobeSocialPgList(STOBE_SOCIAL_FIGHT_COMPONENTS);
        $groups = $this->fetchRows("SELECT COALESCE(detail->>'fight_incident', incident_id) AS fi, lower(detail->>'observer_name') AS o, lower(detail->>'culprit_name') AS c,
              MAX(detail->>'observer_name') AS observer_name, MAX(detail->>'culprit_name') AS culprit_name,
              MAX(CASE WHEN component = ANY(\$2::text[]) THEN timeline_epoch END) AS epoch,
              MAX(CASE WHEN component = ANY(\$2::text[]) THEN observer_key END) AS observer_key,
              MAX(CASE WHEN component = ANY(\$2::text[]) THEN culprit_key END) AS culprit_key,
              bool_or(component = ANY(\$3::text[]) OR (component = 'accident' AND detail->>'level' IN ('knockout', 'maiming'))) AS never,
              MIN(CASE WHEN component = ANY(\$2::text[]) THEN COALESCE((detail->>'unscaled')::int, (detail->>'total')::int, delta) END) AS worst,
              SUM(CASE WHEN component = ANY(\$2::text[]) THEN delta ELSE 0 END) AS charged,
              SUM(CASE WHEN component = ANY(\$4::text[]) THEN delta ELSE 0 END) AS relief,
              SUM(CASE WHEN component = 'grudge_fade' THEN delta ELSE 0 END) AS faded,
              MIN(CASE WHEN component = ANY(\$2::text[]) THEN game_ts END) AS first_ts
            FROM social_effect WHERE campaign_id=\$1 AND applied AND game_ts <= \$5
              AND (component = ANY(\$2::text[]) OR component = ANY(\$4::text[]) OR component = 'grudge_fade')
            GROUP BY 1,2,3 HAVING SUM(CASE WHEN component = ANY(\$2::text[]) THEN delta ELSE 0 END) < 0",
            [$event['campaign_id'], $fight, stobeSocialPgList(STOBE_SOCIAL_NEVER_FADE), stobeSocialPgList(STOBE_SOCIAL_FIGHT_RELIEF), $ts]);
        $out = [];
        foreach ($groups as $g) {
            if ($g['never'] === 't' || (int)$g['worst'] < -$threshold || $g['observer_key'] === null) continue;
            $owed = -(int)$g['charged'] - (int)$g['relief'];
            if ($owed <= 0) continue;
            $fraction = $days <= 0 ? 1.0 : min(1.0, max(0.0, ($ts - (int)$g['first_ts']) / $span));
            $inc = min(100, (int)floor($owed * $fraction) - (int)$g['faded']);
            if ($inc <= 0) continue;
            $row = getNpcData(strval($g['observer_name']));
            if (!is_array($row) || (int)($row['id'] ?? 0) < 1) continue;
            $this->query('SELECT id FROM core_npc WHERE id=$1 FOR UPDATE', [(int)$row['id']]);
            $fresh = getNpcById((int)$row['id']);
            $upd = stobeApplyRelationshipUpdatesMap(stobeGetNpcRelationshipMap($fresh), [['target'=>strval($g['culprit_name']), 'aff_delta'=>$inc,
                'note'=>'The fight with ' . $g['culprit_name'] . ' is fading']]);
            if (($upd['updated'] ?? 0) !== 1) continue;
            $previous = $GLOBALS['gameRequest'] ?? null;
            $GLOBALS['gameRequest'] = ['social', 0, $ts];
            try {
                if (!stobePersistNpcRelationshipMap(strval($fresh['name']), $upd['map'], $fresh)) throw new RuntimeException('Relationship write failed (grudge fade)');
            } finally {
                if ($previous === null) unset($GLOBALS['gameRequest']); else $GLOBALS['gameRequest'] = $previous;
            }
            $detail = ['observer_name'=>$g['observer_name'], 'culprit_name'=>$g['culprit_name'], 'total'=>$inc, 'fight_incident'=>$g['fi'],
                'fraction'=>round($fraction, 4), 'owed'=>$owed, 'reason'=>'grudge_fade'];
            $this->query('INSERT INTO social_effect(campaign_id,timeline_epoch,incident_id,observer_key,culprit_key,component,game_ts,delta,detail,applied,rules_version) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,true,$10) ON CONFLICT DO NOTHING',
                [$event['campaign_id'], strval($g['epoch']), $g['fi'] . '#fade@' . $ts, $g['observer_key'], $g['culprit_key'], 'grudge_fade', $ts, $inc, self::json($detail), $this->rules->version()]);
            $out[] = ['status'=>'grudge_fade', 'component'=>'grudge_fade', 'observer'=>$g['observer_name'], 'culprit'=>$g['culprit_name'], 'delta'=>$inc, 'incident'=>$g['fi']];
        }
        return $out;
    }

    // Interpreter helpers (server-owned; never reachable from client input directly).
''',
      'public function fadeGrudges(')

# ---- rules ----
R = 'lib/social_rules.php'
patch(R, """        $range = $this->config['ranges'][$component] ?? null;
        if (!$range) throw new InvalidArgumentException('Unknown semantic component');""",
      """        // B 55: a caller may supply the range (fights.ranges, an accident's level range).
        $range = $context['range'] ?? ($this->config['ranges'][$component] ?? null);
        if (!$range) throw new InvalidArgumentException('Unknown semantic component');
        if (!is_array($range) || count($range) !== 2 || (int)$range[0] > (int)$range[1]) throw new InvalidArgumentException('Invalid range: ' . $component);
        $range = [(int)$range[0], (int)$range[1]];""",
      'B 55: a caller may supply the range')
patch(R, """        $raw = (int)round($base * $personality * $confidence * $repetition * $affinity * $severity);
        if ($economic) $raw = max(0, min($raw, $this->config['trade_day_cap'] - (int)($context['economic_day_gain'] ?? 0), $this->config['economic_affinity_ceiling'] - $old));
        $total = $raw;""",
      """        $raw = (int)round($base * $personality * $confidence * $repetition * $affinity * $severity);
        if ($economic) $raw = max(0, min($raw, $this->config['trade_day_cap'] - (int)($context['economic_day_gain'] ?? 0), $this->config['economic_affinity_ceiling'] - $old));
        // B 55 item 7: scale (accident 0.25x) and the victim's closeness before the fight; floor -100.
        $scale = (float)($context['scale'] ?? 1.0); $closeness = max(1.0, (float)($context['closeness'] ?? 1.0));
        $unscaled = $raw;
        if (!$positive && ($scale !== 1.0 || $closeness !== 1.0)) {
            $unscaled = (int)round($raw * $scale);
            $raw = max(-100, (int)round($unscaled * $closeness));
        }
        // B 55: a server-computed amount (treatment relief, deal forgiveness), clamped to the component range.
        if (array_key_exists('fixed_total', $context)) $base = $raw = $unscaled = max($range[0], min($range[1], (int)$context['fixed_total']));
        // B 55 item 6: positive gains toward someone with an open fight grudge count at half rate.
        $grudgeRate = $positive && isset($context['grudge_rate']) ? max(0.0, min(1.0, (float)$context['grudge_rate'])) : null;
        if ($grudgeRate !== null) $raw = $unscaled = (int)floor($raw * $grudgeRate);
        $total = $raw;""",
      'B 55 item 7: scale (accident 0.25x)')
patch(R, """        return ['delta'=>$new-$old, 'base'=>$base, 'total'=>$total, 'new_affinity'=>$new, 'rules_version'=>$this->version(),
            'modifiers'=>compact('personality','confidence','repetition','affinity','severity'), 'reason'=>'known_outcome'];
    }
    public static function recruitment(""",
      """        return ['delta'=>$new-$old, 'base'=>$base, 'total'=>$total, 'unscaled'=>$unscaled, 'new_affinity'=>$new, 'rules_version'=>$this->version(),
            'modifiers'=>compact('personality','confidence','repetition','affinity','severity','scale','closeness','grudgeRate'), 'reason'=>'known_outcome'];
    }
    public static function recruitment(""",
      "'unscaled'=>$unscaled, 'new_affinity'")

# ---- interpreter ----
I = 'lib/social_interpreter.php'
patch(I, "        if (str_starts_with($component, 'witness_') || !in_array($result['status'] ?? '', ['shadow', 'enabled'], true)) return [];\n        $total = (int)($result['effect']['total'] ?? 0);",
      "        if (str_starts_with($component, 'witness_') || !in_array($result['status'] ?? '', ['shadow', 'enabled', 'fights'], true)) return [];\n"
      "        // B 55: witnesses feel what happened to the victim, not the victim's personal closeness to the culprit.\n"
      "        $total = (int)($result['effect']['unscaled'] ?? ($result['effect']['total'] ?? 0));",
      "B 55: witnesses feel what happened")
patch(I, """            if ($state['initiator'] !== $a['entity_key']) return [['status'=>'defence', 'basis'=>'retaliation', 'incident'=>$open['id']]];""",
      """            if (!empty($state['spar'])) return [['status'=>'sparring', 'incident'=>$open['id']]]; // B 55 item 3
            if ($state['initiator'] !== $a['entity_key']) return [['status'=>'defence', 'basis'=>'retaliation', 'incident'=>$open['id']]];""",
      "return [['status'=>'sparring', 'incident'=>$open['id']]]; // B 55 item 3")
patch(I, """        $facts = $event['facts'];
        $basis = 'first_strike'; $initiator = $a['entity_key']; $ally = null;""",
      """        $facts = $event['facts'];
        // B 55 item 5: in fights mode only fights that matter count (a squad member, or a named NPC who saw it).
        if ($mode === 'fights' && !stobeSocialFightMatters($event)) return [['status'=>'ignored', 'note'=>'a fight nobody who matters saw (B 55)']];
        // B 55 item 3: a fight both sides agreed to (spar consent) costs nothing unless someone is maimed.
        $spar = stobeSocialFightRulesOn() && stobeSocialSparActive(strval($a['name'] ?? ''), strval($b['name'] ?? ''), (int)$event['game_ts'], $this->rules);
        $basis = 'first_strike'; $initiator = $a['entity_key']; $ally = null;""",
      'B 55 item 5: in fights mode only fights that matter')
patch(I, """            'parties'=>[$a['entity_key']=>$a, $b['entity_key']=>$b], 'opened_ts'=>$event['game_ts'], 'last_ts'=>$event['game_ts'], 'pending'=>(object)[]];
        $this->store->saveIncident($event, $incident, $state);
        if ($initiator !== $a['entity_key']) return [['status'=>'defence', 'basis'=>$basis, 'incident'=>$incident]];""",
      """            'parties'=>[$a['entity_key']=>$a, $b['entity_key']=>$b], 'opened_ts'=>$event['game_ts'], 'last_ts'=>$event['game_ts'], 'pending'=>(object)[]];
        if ($spar) $state['spar'] = true;
        $this->store->saveIncident($event, $incident, $state);
        if ($spar) {
            if (function_exists('stobeLogRelationshipInfo')) stobeLogRelationshipInfo('SOCIAL_SPAR fight', ['a'=>$a['name'] ?? null, 'b'=>$b['name'] ?? null, 'incident'=>$incident]);
            return [['status'=>'sparring', 'incident'=>$incident]];
        }
        if ($initiator !== $a['entity_key']) return [['status'=>'defence', 'basis'=>$basis, 'incident'=>$incident]];""",
      "if ($spar) $state['spar'] = true;")
patch(I, """        if (!$open) return [['status'=>'no_encounter', 'note'=>'harm without an observed attack between this pair is not scored']];""",
      """        // B 55 item 7: friendly fire (squad members, no attack between them) is an accident: 0.25x the level's range.
        if (!$open && stobeSocialFightRulesOn() && self::squadPair($a, $b) && isset($this->combat['harm_levels'][$level])) return [$this->accident($event, $mode, $a, $b, $level)];
        if (!$open) return [['status'=>'no_encounter', 'note'=>'harm without an observed attack between this pair is not scored']];""",
      'B 55 item 7: friendly fire')
patch(I, """        $state['harm'] = array_slice($state['harm'], -32);
        $this->store->saveIncident($event, $open['id'], $state);
""",
      """        $state['harm'] = array_slice($state['harm'], -32);
        $this->store->saveIncident($event, $open['id'], $state);
        if (!empty($state['spar']) && $level !== 'maiming') return [['status'=>'sparring', 'level'=>$level, 'incident'=>$open['id']]]; // B 55 item 3
""",
      "if (!empty($state['spar']) && $level !== 'maiming')")
patch(I, """        if ($ko) {
            $ko['state']['phase'] = 'resolved'; $ko['state']['resolved_ts'] = $event['game_ts'];""",
      """        // B 55 item 7: waking up with severe wounds, bleeding out = critical_harm in the remembered attacker's fight budget.
        if ($ko && $remembered && !empty($ko['state']['encounter']) && stobeSocialFightRulesOn() && $this->wokeBleedingOut($event['facts'])) {
            $enc = $this->store->fetchRows('SELECT state FROM social_incident WHERE campaign_id=$1 AND timeline_epoch=$2 AND incident_id=$3',
                [$event['campaign_id'], $event['timeline_epoch'], $ko['state']['encounter']]);
            $encState = $enc ? json_decode($enc[0]['state'], true) : null;
            if (is_array($encState) && ($encState['initiator'] ?? '') === $remembered['entity_key'] && empty($encState['spar'])) {
                $results[] = $this->effect($event, $mode, $observer, $remembered, 'critical_harm',
                    ['awareness'=>'directly_experienced', 'conscious'=>true, 'note'=>'Woke up bleeding out after ' . $remembered['name'] . ' knocked me out', 'kind'=>'harm'],
                    $ko['state']['encounter'], ['escalation_group'=>self::HARM_GROUP, 'severity'=>$encState['severity'] ?? 1]);
            }
        }
        if ($ko) {
            $ko['state']['phase'] = 'resolved'; $ko['state']['resolved_ts'] = $event['game_ts'];""",
      'B 55 item 7: waking up with severe wounds')
patch(I, """    /**
     * SR06 test switch (general_settings SOCIAL_TEST_FORCE_FIRST_STRIKE""",
      """    /** B 55 item 7: severe wounds on waking (recovered facts with vitals, Stobe B 55 build): near death, or bleeding with low blood. */
    private function wokeBleedingOut(array $facts): bool
    {
        $v = $this->vitals($facts, '');
        if (!$v) return false;
        return $this->nearDeath($v) || ($v['bleed'] > 0.0001 && $v['blood'] <= (float)$this->care('critical_blood', 0.5));
    }

    /**
     * B 55 item 7: friendly fire between squad members without an attack between them: an accident, 0.25x the level's
     * fight range (x closeness). Injury then KO in the same 10 game minutes escalate one budget (only the difference).
     */
    private function accident(array $event, string $mode, array $a, array $b, string $level): array
    {
        $component = $this->combat['harm_levels'][$level];
        $fights = $this->rules->section('fights');
        $pair = substr(hash('sha256', self::pairKey($a['entity_key'], $b['entity_key'])), 0, 16);
        $bucket = intdiv((int)$event['game_ts'], 600);
        $incident = 'accident:' . $bucket . ':' . $level . ':' . $pair;
        $prior = $this->store->fetchRows("SELECT MIN((detail->>'total')::int) AS worst FROM social_effect WHERE campaign_id=\\$1 AND timeline_epoch=\\$2 AND component='accident'
              AND observer_key=\\$3 AND culprit_key=\\$4 AND incident_id LIKE \\$5", [$event['campaign_id'], $event['timeline_epoch'], $b['entity_key'], $a['entity_key'], 'accident:' . $bucket . ':%:' . $pair]);
        $context = ['scale'=>(float)($fights['accident_scale'] ?? 0.25), 'prior_total'=>min(0, (int)($prior[0]['worst'] ?? 0)),
            'fight_incident'=>'accident:' . $bucket . ':' . $pair, 'level'=>$level];
        if (isset($fights['ranges'][$component])) $context['range'] = $fights['ranges'][$component];
        elseif (isset($this->rules->section('ranges')[$component])) $context['range'] = $this->rules->section('ranges')[$component];
        $conscious = $level === 'knockout' ? true : ($b['conscious'] ?? null);
        $result = $this->effect($event, $mode, $b, $a, 'accident', self::awareness($conscious) + ['note'=>'Hurt by accident by ' . $a['name'], 'kind'=>'accident'], $incident, $context);
        if ($conscious === false) $this->latent($event, $b, $a, 'accident', $incident);
        return $result;
    }

    /**
     * SR06 test switch (general_settings SOCIAL_TEST_FORCE_FIRST_STRIKE""",
      'private function accident(')

# ---- care: item 8 ----
C = 'lib/social_care.php'
patch(C, "        if ($this->helperCausedHarm($event, $p, $r)) return [['status'=>'no_trust_from_own_harm', 'component'=>$class]];\n",
      """        if ($this->helperCausedHarm($event, $p, $r)) {
            // B 55 item 8: the attacker himself treating her wounds takes 15-30 % off that fight's penalty (never positive trust).
            $relief = stobeSocialFightRulesOn() ? $this->treatedRelief($event, $mode, $p, $r) : null;
            return $relief ? [['status'=>'no_trust_from_own_harm', 'component'=>$class], $relief] : [['status'=>'no_trust_from_own_harm', 'component'=>$class]];
        }
""",
      'B 55 item 8: the attacker himself treating')
patch(C, "    private function carryStart(array $event, string $mode): array\n",
      r'''    /** B 55 item 8: relief for the latest fight the provider started against the recipient (once per fight). */
    private function treatedRelief(array $event, string $mode, array $p, array $r): ?array
    {
        $rows = $this->store->fetchRows("SELECT incident_id,state FROM social_incident WHERE campaign_id=\$1 AND timeline_epoch=\$2 AND state->>'kind'='combat'
              AND state->>'victim'=\$3 AND state->>'initiator'=\$4 AND game_ts<=\$5 AND game_ts>=\$6 ORDER BY game_ts DESC LIMIT 1",
            [$event['campaign_id'], $event['timeline_epoch'], $r['entity_key'], $p['entity_key'], $event['game_ts'], $event['game_ts'] - (int)$this->care('own_harm_window_seconds', 86400)]);
        if (!$rows) return null;
        $incident = $rows[0]['incident_id'];
        $state = json_decode($rows[0]['state'], true);
        $net = $this->store->fetchRows("SELECT COALESCE(SUM(delta),0) AS s FROM social_effect WHERE campaign_id=\$1 AND applied AND COALESCE(detail->>'fight_incident', incident_id)=\$2
              AND observer_key=\$3 AND culprit_key=\$4", [$event['campaign_id'], $incident, $r['entity_key'], $p['entity_key']]);
        $penalty = (int)($net[0]['s'] ?? 0);
        if ($penalty >= 0) return ['status'=>'no_fight_penalty', 'component'=>'treated_relief', 'incident'=>$incident];
        $share = stobeSocialTreatedShare($incident, strval($r['name']), (int)$event['game_ts'] - (int)($state['last_ts'] ?? $event['game_ts']), $this->rules);
        $amount = min(-$penalty, max(1, (int)round(-$penalty * $share)));
        $resolve = static fn(string $key) => SocialIdentity::resolve($key === $r['entity_key'] ? $r : $p, $key === $r['entity_key'] ? 'observer' : 'culprit');
        $result = $this->store->apply($event, $r['entity_key'], $p['entity_key'], 'treated_relief',
            ['responsible_entity'=>$p['entity_key'], 'awareness'=>'verified_aid', 'confidence'=>'certain', 'conscious'=>$r['conscious'] ?? null,
             'note'=>$p['name'] . ' treated my wounds after our fight', 'kind'=>'aid'],
            $resolve, $mode, ['fixed_total'=>$amount], $incident);
        return ['component'=>'treated_relief', 'observer'=>$r['name'], 'culprit'=>$p['name'], 'share'=>round($share, 3), 'penalty'=>$penalty] + $result;
    }

    private function carryStart(array $event, string $mode): array
''',
      'private function treatedRelief(')

# ---- agreements: item 2 ----
A = 'lib/social_agreements.php'
patch(A, "    $mode = stobeSocialMode();\n    if ($mode === 'off' || !getSettingBool('SOCIAL_CATEGORY_AGREEMENTS', true)) return false;",
      "    $mode = stobeSocialIngestMode(); // B 55: fights mode scores deal outcomes too\n    if ($mode === 'off' || !getSettingBool('SOCIAL_CATEGORY_AGREEMENTS', true)) return false;",
      'stobeSocialIngestMode(); // B 55: fights mode scores')
patch(A, "        if ($event === null) return $mode === 'enabled'; // already recorded (retry): legacy must not double-apply either",
      "        if ($event === null) return in_array($mode, ['enabled', 'fights'], true); // already recorded (retry): legacy must not double-apply either",
      "if ($event === null) return in_array($mode, ['enabled', 'fights'], true);")
patch(A, """        }
        return $mode === 'enabled';
    } catch (Throwable $e) {""",
      """        }
        // B 55 item 2: a kept deal wins back 1/3 x how fully it was kept x the NPC's forgiveness of the latest fight's penalty.
        if ($status === 'COMPLETE' && stobeSocialFightRulesOn()) {
            [$fightIncident, $penalty] = stobeSocialLatestFight(strval($npcRow['name']), $player);
            if ($fightIncident !== null && $penalty < 0) {
                $share = (float)((new SocialRules())->section('fights')['deal_share'] ?? 0.3333);
                $kept = stobeSocialDealKeptness($termState); $forgive = stobeSocialForgiveness($npcRow);
                $amount = (int)round(-$penalty * $share * $kept * $forgive);
                $result = $amount > 0 ? $store->apply($event, $npc['entity_key'], $playerEntity['entity_key'], 'deal_forgiveness',
                    ['responsible_entity'=>$playerEntity['entity_key'], 'awareness'=>'directly_experienced', 'confidence'=>'certain', 'conscious'=>true,
                     'note'=>$player . ' kept our deal after the fight', 'kind'=>'agreement'], $resolve, $mode, ['fixed_total'=>$amount], $fightIncident) : ['status'=>'nothing_to_forgive'];
                if (function_exists('stobeLogRelationshipInfo')) stobeLogRelationshipInfo('SOCIAL_INTERPRET', ['mode'=>$mode, 'kind'=>'agreement', 'contract'=>$contract,
                    'component'=>'deal_forgiveness', 'npc'=>$npc['name'], 'penalty'=>$penalty, 'kept'=>round($kept, 3), 'forgiveness'=>$forgive,
                    'result'=>$result['status'] ?? null, 'delta'=>$result['effect']['delta'] ?? null]);
            }
        }
        return in_array($mode, ['enabled', 'fights'], true);
    } catch (Throwable $e) {""",
      'B 55 item 2: a kept deal wins back')

patch(A, "        $event = $store->recordInternal($scope, $mode, 'agreement:' . $contract . ':' . $status, function_exists('stobeNegLatestGamets') ? max(0, stobeNegLatestGamets()) : 0,",
      "        $event = $store->recordInternal($scope, $mode, 'agreement:' . $contract . ':' . $status, stobeSocialNowGameTs(), // B 55: never 0 when the game sent nothing recently",
      'stobeSocialNowGameTs(), // B 55: never 0')

# ---- dialogue: items 4 + 6 ----
patch('lib/social_dialogue.php',
      "{\n    if (!$updates || stobeSocialMode() !== 'enabled' || !getSettingBool('SOCIAL_CATEGORY_DIALOGUE', true)) return $updates;",
      "{\n    require_once __DIR__ . '/social_fights.php';\n"
      "    $updates = stobeSocialFightDialogueRules($speaker, $updates); // B 55 items 4 + 6: no chat gains a game day after a fight, half while a fight grudge is open\n"
      "    if (!$updates || stobeSocialMode() !== 'enabled' || !getSettingBool('SOCIAL_CATEGORY_DIALOGUE', true)) return $updates;",
      'stobeSocialFightDialogueRules($speaker, $updates); // B 55')

# ---- chat helper ----
H = 'lib/chat_helper_functions.php'
patch(H, "    if (stobeSocialMode() === 'enabled') return [];\n    if (function_exists('getSettingBool') && !getSettingBool('RELATIONSHIP_FIGHTS_COUNT', true)) return [];",
      "    if (in_array(stobeSocialIngestMode(), ['enabled', 'fights'], true)) return []; // B 55: R4 retired while REL scores fights\n"
      "    if (function_exists('getSettingBool') && !getSettingBool('RELATIONSHIP_FIGHTS_COUNT', true)) return [];",
      'B 55: R4 retired while REL scores fights')
patch(H, """    $aff = intval($entry['aff'] ?? ($entry['affinity'] ?? 0));
    return stobeRelationshipStanceText($speaker, $aff, strval($entry['type'] ?? ''), $sameSquad, strval($entry['note'] ?? ''));""",
      """    $aff = intval($entry['aff'] ?? ($entry['affinity'] ?? 0));
    $block = stobeRelationshipStanceText($speaker, $aff, strval($entry['type'] ?? ''), $sameSquad, strval($entry['note'] ?? ''));
    require_once __DIR__ . '/social_fights.php';
    $memory = stobeSocialFightMemoryLine($npcName, $speaker); // B 55 item 6: the first fight leaves a mark
    if ($memory !== '' && $block !== '') $block = str_replace('</how_you_feel_about_them>', '  <memory>' . stobePromptXmlEscape($memory) . "</memory>\\n</how_you_feel_about_them>", $block);
    return $block;""",
      'B 55 item 6: the first fight leaves a mark')
patch(H, "    $rawActionTag = stobeSocialTestForceJoinAttempt($rawActionTag, $character, $eventType); // SR30 test switch, off by default\n",
      "    $rawActionTag = stobeSocialTestForceJoinAttempt($rawActionTag, $character, $eventType); // SR30 test switch, off by default\n"
      "    require_once __DIR__ . '/social_fights.php';\n"
      "    stobeSocialNoteSparConsent($character, $message, $eventType); // B 55 item 3: a spar both sides agreed to\n",
      'B 55 item 3: a spar both sides agreed to')

# ---- rules JSON ----
rp = os.path.join(ROOT, 'data/social_relationship_rules.json')
with open(rp, encoding='utf-8') as f:
    rules = json.load(f)
if 'fights' not in rules:
    rules['ranges']['treated_relief'] = [0, 100]
    rules['ranges']['deal_forgiveness'] = [0, 100]
    rules['categories']['treated_relief'] = 'combat'
    rules['categories']['deal_forgiveness'] = 'agreements'
    rules['fights'] = {
        'ranges': {'aggression': [-15, -10], 'injury': [-30, -23], 'serious_assault': [-50, -40], 'critical_harm': [-65, -55], 'maiming': [-78, -68]},
        'closeness': [[31, 1.3], [56, 2.0], [76, 2.5], [91, 3.0]],
        'accident_scale': 0.25,
        'fade_threshold': 30,
        'fade_days': 14,
        'fade_check_seconds': 600,
        'spar_window_seconds': 3600,
        'grudge_positive_rate': 0.5,
        'chat_cooldown_seconds': 86400,
        'deal_share': 0.3333,
        'treated_share': [0.15, 0.30],
        'treated_soon_seconds': 21600,
        'note': 'B 55 (SOCIAL_FIGHT_RULES=b55, default): ranges = victim state when the fight ends/she wakes (not hurt, wounded standing, KO moderate, bleeding out, limb); x closeness (victim -> attacker before the fight, from aff >=) floor -100; accident = scale x level range; incidents with no KO-or-worse and unscaled worst >= -fade_threshold fade linearly over fade_days (settings SOCIAL_GRUDGE_FADE_THRESHOLD/DAYS); treated_share 15-30 % (more the sooner within treated_soon_seconds, seeded per incident); deal_share x keptness x forgiveness.',
    }
    with open(rp, 'w', encoding='utf-8') as f:
        f.write(json.dumps(rules, indent=1) + '\n')
    print('patch data/social_relationship_rules.json: fights section')
else:
    print('skip  data/social_relationship_rules.json')

# ---- inspect tool ----
T = 'tools/social_relationship_inspect.php'
patch(T, " *   php tools/social_relationship_inspect.php --purge-all --yes",
      """ *   php tools/social_relationship_inspect.php --add-spar "A" "B" [game_ts]   TEST SETUP (B 55): record spar consent between A and B
 *                                                  (game_ts default: the latest game time; a fight between them within 1 game hour is free)
 *   php tools/social_relationship_inspect.php --set-switch SOCIAL_FIGHTS_LIVE|SOCIAL_FIGHT_RULES|SOCIAL_GRUDGE_FADE_DAYS|SOCIAL_GRUDGE_FADE_THRESHOLD <value|off>
 *                                                  B 55 settings (off = back to the default: live, b55, 14 days, 30)
 *   php tools/social_relationship_inspect.php --purge-all --yes""",
      '--add-spar "A" "B" [game_ts]')
patch(T, "    if (!in_array($id, ['SOCIAL_TEST_FORCE_JOIN_ATTEMPT', 'SOCIAL_TEST_FORCE_FIRST_STRIKE'], true) || $value === '') {",
      "    if (!in_array($id, ['SOCIAL_TEST_FORCE_JOIN_ATTEMPT', 'SOCIAL_TEST_FORCE_FIRST_STRIKE', 'SOCIAL_FIGHTS_LIVE', 'SOCIAL_FIGHT_RULES', 'SOCIAL_GRUDGE_FADE_DAYS', 'SOCIAL_GRUDGE_FADE_THRESHOLD'], true) || $value === '') {",
      "'SOCIAL_GRUDGE_FADE_DAYS', 'SOCIAL_GRUDGE_FADE_THRESHOLD'], true) || $value === '') {")
patch(T, "if (($i = array_search('--retention', $args, true)) !== false) {",
      """if (($i = array_search('--add-spar', $args, true)) !== false) {
    // TEST SETUP (B 55 item 3): spar consent between two characters, as if both agreed in dialogue.
    $sa = strval($args[$i+1] ?? ''); $sb = strval($args[$i+2] ?? '');
    $sts = isset($args[$i+3]) && is_numeric($args[$i+3]) ? (int)$args[$i+3] : stobeSocialNowGameTs();
    if ($sa === '' || $sb === '') { fwrite(STDERR, "--add-spar A B [game_ts]\\n"); exit(2); }
    $ok = stobeSocialRecordSpar($sa, $sb, $sts, 'test_setup');
    echo json_encode(['add_spar'=>$ok, 'a'=>$sa, 'b'=>$sb, 'game_ts'=>$sts]), "\\n";
    exit($ok ? 0 : 1);
}
if (($i = array_search('--retention', $args, true)) !== false) {""",
      "array_search('--add-spar', $args, true)")
patch(T, """    'mode' => stobeSocialMode(),
    'settings' => [""",
      """    'mode' => stobeSocialMode(),
    'ingest_mode' => stobeSocialIngestMode(),
    'fight_rules' => stobeSocialFightRulesOn() ? 'b55' : 'rel',
    'settings' => [
        'SOCIAL_FIGHTS_LIVE' => $setting('SOCIAL_FIGHTS_LIVE'),
        'SOCIAL_GRUDGE_FADE_DAYS' => $setting('SOCIAL_GRUDGE_FADE_DAYS'),
        'SOCIAL_GRUDGE_FADE_THRESHOLD' => $setting('SOCIAL_GRUDGE_FADE_THRESHOLD'),""",
      "'ingest_mode' => stobeSocialIngestMode(),")

# ---- tests that pin the legacy (non-REL) behaviour ----
patch('tests/relationship_stance_regression.php',
      "$r4 = stobeRelationshipOnAttack('Ann4 [Rel4]: Initiated attack (talking to: Bob4 [Rel4])', 1000000);",
      "// B 55: R4 only runs with REL fights mode off (SOCIAL_FIGHTS_LIVE=false and SOCIAL_RELATIONSHIP_MODE off).\n"
      "$GLOBALS['db']->exec(\"DELETE FROM general_settings WHERE id IN ('SOCIAL_FIGHTS_LIVE','SOCIAL_RELATIONSHIP_MODE')\");\n"
      "check('B 55: R4 retired while REL scores fights (default)', stobeRelationshipOnAttack('Ann4 [Rel4]: Initiated attack (talking to: Bob4 [Rel4])', 999000) === []);\n"
      "$GLOBALS['db']->exec(\"INSERT INTO general_settings(id,value) VALUES('SOCIAL_FIGHTS_LIVE','false') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value\");\n"
      "$r4 = stobeRelationshipOnAttack('Ann4 [Rel4]: Initiated attack (talking to: Bob4 [Rel4])', 1000000);",
      'B 55: R4 retired while REL scores fights (default)')
patch('tests/relationship_stance_regression.php',
      "check('R4: generic names are skipped', stobeRelationshipOnAttack('Rel4: Initiated attack (talking to: Bob4 [Rel4])', 1000200) === []);\n",
      "check('R4: generic names are skipped', stobeRelationshipOnAttack('Rel4: Initiated attack (talking to: Bob4 [Rel4])', 1000200) === []);\n"
      "$GLOBALS['db']->exec(\"DELETE FROM general_settings WHERE id='SOCIAL_FIGHTS_LIVE'\");\n",
      "DELETE FROM general_settings WHERE id='SOCIAL_FIGHTS_LIVE'\");\n")
patch('tests/social_property_regression.php',
      """    sql("UPDATE general_settings SET value='off' WHERE id='SOCIAL_RELATIONSHIP_MODE'");
    sql("INSERT INTO stobe_social_contract(contract_id,npc_name,player_name,status,terms,kind) VALUES('reltest-6'""",
      """    sql("UPDATE general_settings SET value='off' WHERE id='SOCIAL_RELATIONSHIP_MODE'");
    sql("INSERT INTO general_settings(id,value) VALUES('SOCIAL_FIGHTS_LIVE','false') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value"); // B 55: fights mode off = legacy
    sql("INSERT INTO stobe_social_contract(contract_id,npc_name,player_name,status,terms,kind) VALUES('reltest-6'""",
      "('SOCIAL_FIGHTS_LIVE','false') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value\"); // B 55: fights mode off")
patch('tests/social_property_regression.php',
      """    sql("DELETE FROM stobe_social_contract WHERE contract_id LIKE 'reltest%'");""",
      """    sql("DELETE FROM stobe_social_contract WHERE contract_id LIKE 'reltest%'");
    sql("DELETE FROM general_settings WHERE id='SOCIAL_FIGHTS_LIVE'");""",
      """WHERE contract_id LIKE 'reltest%'");
    sql("DELETE FROM general_settings WHERE id='SOCIAL_FIGHTS_LIVE'");""")
# Phase-8 REL suites pin the old ranges/behaviour: they run with SOCIAL_FIGHT_RULES=rel (B 55 has its own suite).
for suite in ('tests/social_combat_regression.php', 'tests/social_unconscious_regression.php', 'tests/social_care_regression.php'):
    patch(suite,
          """sql("INSERT INTO general_settings(id,value) VALUES('SOCIAL_RELATIONSHIP_MODE','enabled') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value");\n""",
          """sql("INSERT INTO general_settings(id,value) VALUES('SOCIAL_RELATIONSHIP_MODE','enabled') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value");\n"""
          """sql("INSERT INTO general_settings(id,value) VALUES('SOCIAL_FIGHT_RULES','rel') ON CONFLICT(id) DO UPDATE SET value=EXCLUDED.value"); // B 55 rules: tests/social_fights_regression.php\n""",
          "('SOCIAL_FIGHT_RULES','rel')")
    patch(suite,
          """sql("UPDATE general_settings SET value='off' WHERE id='SOCIAL_RELATIONSHIP_MODE'");\n""",
          """sql("UPDATE general_settings SET value='off' WHERE id='SOCIAL_RELATIONSHIP_MODE'");\nsql("DELETE FROM general_settings WHERE id='SOCIAL_FIGHT_RULES'");\n""",
          "DELETE FROM general_settings WHERE id='SOCIAL_FIGHT_RULES'")
print('done')
