<?php
// Item 100 (m16 Full-Base, squad Beaks/Avarek, PLAYER_NAME "shay"): the server addressed the player by the
// PLAYER_NAME persona instead of the character who spoke. Avarek's correct GIVE_ITEM@Beaks got a duplicate
// GIVE_ITEM@Shay (item 43 helper only knew "shay") -> Beaks got 2 Bread; "me" destinations became "Shay"; and every
// player-only path (voice payment, deals, refusals, worn items, loot) was off because speaker "Beaks" != "shay".
// Shay's call (2026-10-03): (1) server-built action targets use the speaking player character; (2) "player speaking" =
// an inputtext speaker or PLAYER_NAME; (a) PLAYER_NAME stays the persona for reputation/relationship history.
//   - stobePlayerActorName(): the player character speaking in this request ($GLOBALS STOBE_PLAYER_ACTOR), else the
//     PLAYER_NAME persona; stobePlayerPersonaName(): PLAYER_NAME.
//   - chat.php: inputtext/inputtext_s speakers are the player; $playerName becomes that character for the request.
//   - item 43/67 helper: a GIVE_ITEM to the player character, the persona or any player-squad member counts.
//   - goals: "me" = the speaking character; the engine's tick/dispatch use the deal's own player_name for action
//     targets; deal consequences keep the persona as the reputation/relationship key.
// Usage: php item100_player_actor.php <tree root>   (asserts anchors; refuses a second run)
$root = rtrim($argv[1] ?? '', '/');
function p100(string $path, array $edits): void {
    $s = file_get_contents($path);
    if ($s === false) { fwrite(STDERR, "cannot read $path\n"); exit(1); }
    if (str_contains($s, 'Item 100')) { fwrite(STDERR, "$path already has item 100\n"); exit(1); }
    foreach ($edits as [$a, $b]) {
        if (substr_count($s, $a) !== 1) { fwrite(STDERR, "anchor missing/not unique in $path: " . substr($a, 0, 90) . "\n"); exit(1); }
        $s = str_replace($a, $b, $s);
    }
    file_put_contents($path, $s); echo "patched $path\n";
}

// --- helpers (chat_helper_functions.php is loaded for every request and by the tests)
p100("$root/lib/chat_helper_functions.php", [
[<<<'A'
function stobeInferMissingHandovers(string $playerLine, array|false $npcData, array $actions, string $reply, string $playerName, ?bool $squadMember = null): array {
    if ($playerName === '' || !is_array($npcData) || !function_exists('stobeNegInventoryCounts')
        || !function_exists('stobeNegItemMatchesTerm')) return [];
    $given = [];
    foreach ($actions as $a) {
        $parts = explode('@', strval($a));
        if (strtoupper(trim($parts[0])) !== 'GIVE_ITEM' || count($parts) < 3) continue;
        if (strcasecmp(trim($parts[1]), $playerName) !== 0 && strtolower(trim($parts[1])) !== 'player') continue;
A, <<<'B'
/** Item 100: the PLAYER_NAME persona (reputation/relationship history key, Shay's call (a)). */
function stobePlayerPersonaName(): string {
    return function_exists('getSetting') ? normalizeParticipantNameToken(strval(getSetting('PLAYER_NAME', 'Drifter'))) : '';
}

/** Item 100: the player character speaking in this request (chat.php sets it), else the persona. */
function stobePlayerActorName(): string {
    $actor = normalizeParticipantNameToken(strval($GLOBALS['STOBE_PLAYER_ACTOR'] ?? ''));
    return $actor !== '' ? $actor : stobePlayerPersonaName();
}

/** Item 100: a name that means the player side: the speaking character, the persona, "player", or a squad member. */
function stobeIsPlayerSideName(string $name, string $playerName): bool {
    $n = normalizeParticipantNameToken($name);
    if ($n === '') return false;
    if (strcasecmp($n, $playerName) === 0 || strtolower($n) === 'player') return true;
    if (strcasecmp($n, stobePlayerActorName()) === 0 || strcasecmp($n, stobePlayerPersonaName()) === 0) return true;
    return function_exists('stobeNegIsPlayerSide') && stobeNegIsPlayerSide($n, $playerName);
}

function stobeInferMissingHandovers(string $playerLine, array|false $npcData, array $actions, string $reply, string $playerName, ?bool $squadMember = null): array {
    if ($playerName === '' || !is_array($npcData) || !function_exists('stobeNegInventoryCounts')
        || !function_exists('stobeNegItemMatchesTerm')) return [];
    $given = [];
    foreach ($actions as $a) {
        $parts = explode('@', strval($a));
        if (strtoupper(trim($parts[0])) !== 'GIVE_ITEM' || count($parts) < 3) continue;
        if (!stobeIsPlayerSideName(trim($parts[1]), $playerName)) continue; // Item 100: any player-side name
B],
]);

// --- chat.php: the speaking player character
p100("$root/processor/chat.php", [
[<<<'A'
$speaker = $parts[0] ?? getSetting('PLAYER_NAME', 'Drifter');
$playerName = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
A, <<<'B'
$speaker = $parts[0] ?? getSetting('PLAYER_NAME', 'Drifter');
$playerName = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
// Item 100: the player types as whichever squad member is selected (Beaks, not the PLAYER_NAME persona "shay").
// For this request "the player" is that character: actions, goals and deals target it, player-only paths run.
$stobeSpeakerToken = normalizeParticipantNameToken(strval($speaker));
if ($stobeSpeakerToken !== '' && strcasecmp($stobeSpeakerToken, $playerName) !== 0
    && in_array(strtolower(strval($eventType ?? '')), ['inputtext', 'inputtext_s'], true)) {
    stobeLogInfo('Player speaks as a squad character (item 100)', ['speaker' => $stobeSpeakerToken, 'persona' => $playerName]);
    $playerName = $stobeSpeakerToken;
}
$GLOBALS['STOBE_PLAYER_ACTOR'] = $playerName;
B],
[<<<'A'
        trim(strval(getSetting('PLAYER_NAME', ''))));
A, <<<'B'
        $playerName); // Item 100: the speaking player character
B],
]);

// --- goals: "me" = the speaking character
p100("$root/lib/work_goal_functions.php", [
[<<<'A'
    if (preg_match('/^(?:me|myself|us|player|the\s+player)$/i', $req)) {
        return function_exists('getSetting') ? trim(strval(getSetting('PLAYER_NAME', ''))) : '';
    }
A, <<<'B'
    if (preg_match('/^(?:me|myself|us|player|the\s+player)$/i', $req)) {
        if (function_exists('stobePlayerActorName')) return stobePlayerActorName(); // Item 100
        return function_exists('getSetting') ? trim(strval(getSetting('PLAYER_NAME', ''))) : '';
    }
B],
[<<<'A'
    $player = function_exists('getSetting') ? strtolower(trim(strval(getSetting('PLAYER_NAME', '')))) : '';
    if ($player !== '' && $req === $player) return 'person';
A, <<<'B'
    $player = function_exists('getSetting') ? strtolower(trim(strval(getSetting('PLAYER_NAME', '')))) : '';
    if ($player !== '' && $req === $player) return 'person';
    if (function_exists('stobePlayerActorName') && $req === strtolower(stobePlayerActorName())) return 'person'; // Item 100
B],
]);

// --- negotiation engine: deal actions target the deal's player character; consequences keep the persona
p100("$root/lib/negotiation_engine.php", [
[<<<'A'
    foreach (is_array($rows) ? $rows : [] as $deal) {
        try {
            stobeNegTickDeal($deal, $player, $now);
A, <<<'B'
    foreach (is_array($rows) ? $rows : [] as $deal) {
        try {
            // Item 100: action targets go to the character the deal was made with (deal player_name)
            $dealPlayer = normalizeParticipantNameToken(strval($deal['player_name'] ?? ''));
            stobeNegTickDeal($deal, $dealPlayer !== '' ? $dealPlayer : $player, $now);
B],
[<<<'A'
    $state = stobeNegDecode($deal['term_state'] ?? []);
    $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
    $sent = array_map('strtolower', $finalActions);
A, <<<'B'
    $state = stobeNegDecode($deal['term_state'] ?? []);
    $player = normalizeParticipantNameToken(strval($deal['player_name'] ?? '')); // Item 100: the deal's character
    if ($player === '') $player = normalizeParticipantNameToken(getSetting('PLAYER_NAME', 'Drifter'));
    $sent = array_map('strtolower', $finalActions);
B],
[<<<'A'
        $state = stobeNegDecode($deal['term_state'] ?? []);
        $summary = stobeNegTermsSummary($state, $npc, $player);
A, <<<'B'
        $state = stobeNegDecode($deal['term_state'] ?? []);
        $summary = stobeNegTermsSummary($state, $npc, $player);
        // Item 100 (Shay's call (a)): reputation and relationship history stay keyed by the PLAYER_NAME persona.
        // Only a player-squad character other than the persona is mapped (a deal made as Beaks counts for "shay").
        $persona = normalizeParticipantNameToken(strval(getSetting('PLAYER_NAME', '')));
        if ($persona === '' || strcasecmp($persona, $player) === 0 || !stobeNegIsPlayerSide($player, $persona)) $persona = $player;
B],
[<<<'A'
                $applied = stobeApplyRelationshipUpdatesMap(stobeGetNpcRelationshipMap($npcData), [[
                    'target'=>$player, 'aff_delta'=>$delta, 'type'=>'',
                    'note'=>$status === 'COMPLETE' ? 'Kept a deal' : 'Broke a deal',
                ]], [$player]);
A, <<<'B'
                $applied = stobeApplyRelationshipUpdatesMap(stobeGetNpcRelationshipMap($npcData), [[
                    'target'=>$persona, 'aff_delta'=>$delta, 'type'=>'',
                    'note'=>$status === 'COMPLETE' ? 'Kept a deal' : 'Broke a deal',
                ]], [$persona]);
B],
[<<<'A'
                 ON CONFLICT (player_name) DO UPDATE SET {$repColumn}=stobe_negotiation_reputation.{$repColumn}+1, updated_at=NOW()", // item 50: key is lower-case
                [strtolower($player)] /* item 50 */
A, <<<'B'
                 ON CONFLICT (player_name) DO UPDATE SET {$repColumn}=stobe_negotiation_reputation.{$repColumn}+1, updated_at=NOW()", // item 50: key is lower-case
                [strtolower($persona)] /* item 50; Item 100: persona */
B],
]);

// --- regression
p100("$root/tests/negotiation_engine_regression.php", [
[<<<'A'
// ---------------------------------------------------------------- cleanup
A, <<<'B'
// ---------------------------------------------------------------- Item 100: another squad than the PLAYER_NAME persona
// Speaker "NegTestBeaks" (a player-faction character), persona $player: the item 43 helper must not add a second
// GIVE_ITEM for the persona; "me" is the speaking character; deal actions target it; the reputation key stays the persona.
fixtureNpc('NegTestBeaks', ['money'=>800, 'money_observed_at'=>time()], '', '', '100/100', 'Nameless');
fixtureNpc('NegTestAvarek', ['money'=>10, 'money_observed_at'=>time()], 'Bread x2 value 10', 'Loyal.', '100/100', 'Nameless');
$GLOBALS['STOBE_PLAYER_ACTOR'] = 'NegTestBeaks';
$avarek = getNpcData('NegTestAvarek');
$extra = stobeInferMissingHandovers('NegTestAvarek, give me one of your bread.', $avarek, ['GIVE_ITEM@NegTestBeaks@Bread@1'],
    'Here you go.', 'NegTestBeaks', true);
check('item 100: GIVE_ITEM to the speaking character counts (no extra GIVE_ITEM@persona)', $extra === [], $extra);
$extra2 = stobeInferMissingHandovers('NegTestAvarek, give me one of your bread.', $avarek, ['GIVE_ITEM@' . $player . '@Bread@1'],
    'Here you go.', 'NegTestBeaks', true);
check('item 100: GIVE_ITEM to the persona also counts', $extra2 === [], $extra2);
check('item 100: "me" is the speaking character', stobeGoalPersonName('me') === 'NegTestBeaks', stobeGoalPersonName('me'));
$chatSrc100 = file_get_contents(__DIR__ . '/../processor/chat.php');
check('item 100: chat.php makes an inputtext speaker the player', str_contains($chatSrc100, "\$GLOBALS['STOBE_PLAYER_ACTOR'] = \$playerName;")
    && str_contains($chatSrc100, "['inputtext', 'inputtext_s']"));
$id = makeDeal('NegTestBandit', [['kind'=>'GIVE_CATS','by'=>'npc','to'=>'player','amount'=>20]], 'social');
$db->exec("UPDATE stobe_social_contract SET player_name='NegTestBeaks' WHERE contract_id=$1", [$id]);
stobeNegBeginPerformance($id, ['GIVE_CATS@NegTestBeaks@20'], 'NegTestBeaks', 1000, '');
check('item 100: the deal payment is dispatched to the speaking character', termStatus($id, 0) === 'DISPATCHED', termStatus($id, 0));
$repBefore = intval($db->fetchOne("SELECT COALESCE(MAX(npc_kept),0) AS k FROM stobe_negotiation_reputation WHERE player_name=LOWER($1)", [$player])['k'] ?? 0);
stobeLine("ACTION_EXEC: GIVE_CATS actor=NegTestBandit recipient=NegTestBeaks amount=20", time());
stobeNegTick();
check('item 100: deal with the squad character completes', status($id) === 'COMPLETE', [status($id), termStatus($id, 0)]);
$beaksRep = $db->fetchOne("SELECT 1 AS x FROM stobe_negotiation_reputation WHERE player_name='negtestbeaks'");
check('item 100: reputation stays on the persona (no row for the character)', !$beaksRep);
unset($GLOBALS['STOBE_PLAYER_ACTOR']);
check('item 100: without a speaking character, "me" is the persona (Shay/Malzin unchanged)', strcasecmp(stobeGoalPersonName('me'), $player) === 0, stobeGoalPersonName('me'));
foreach (['NegTestBeaks', 'NegTestAvarek'] as $n) { $db->exec("DELETE FROM core_npc_master WHERE name=$1", [$n]); $db->exec("DELETE FROM core_npc WHERE name=$1", [$n]); }

// ---------------------------------------------------------------- cleanup
B],
]);
