#!/usr/bin/env python3
"""STOBE test switches (Shay 2026-10-03): rows that need a rare LLM choice can be forced in game.

- lib/negotiation_test_switches.php (new; source: pending-fixes/neg_test_switches/negotiation_test_switches.php):
  NEG_TEST_INJECT (overrides fields of the model's structured reply for the next matching turns) and
  NEG_TEST_FORCE_INITIATIVE (queues a surrender/assist offer without the health/cooldown gates). Both general_settings,
  off by default, logged when they fire.
- lib/bootstrap.php: loads it.
- connector/llm_dispatcher.php: stobeCallLLMStream runs the injection when meta stobe_test_inject is set.
- processor/chat.php + processor/bored.php: take the injection for the player's chat turn / a negotiation directive turn.
- lib/negotiation_engine.php: stobeNegConsiderInitiatives honours NEG_TEST_FORCE_INITIATIVE.

Usage: neg_test_switches.py <tree root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1])
here = pathlib.Path(__file__).resolve().parent

def patch(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already patched"); return
    assert s.count(old) == 1, f"{rel}: anchor found {s.count(old)}x"
    p.write_text(s.replace(old, new))
    print(f"{rel}: patched")

# new files (the library and its regression suite)
for name, rel in (("negotiation_test_switches.php", "lib/negotiation_test_switches.php"),
                  ("negotiation_test_switches_regression.php", "tests/negotiation_test_switches_regression.php")):
    src = (here / "neg_test_switches" / name).read_text()
    dst = root / rel
    if dst.exists() and dst.read_text() == src:
        print(f"{rel}: already in place")
    else:
        dst.write_text(src)
        print(f"{rel}: written")

patch("lib/bootstrap.php",
"""require_once($enginePath . 'lib' . DIRECTORY_SEPARATOR . 'negotiation_engine.php');""",
"""require_once($enginePath . 'lib' . DIRECTORY_SEPARATOR . 'negotiation_engine.php');
require_once($enginePath . 'lib' . DIRECTORY_SEPARATOR . 'negotiation_test_switches.php'); // test switches, off by default""")

patch("connector/llm_dispatcher.php",
"""    callable $onTextDelta,
    array $meta = []
): string|false {
    $runtime = stobePrepareLlmRuntimeConfig($config);""",
"""    callable $onTextDelta,
    array $meta = []
): string|false {
    if (is_array($meta['stobe_test_inject'] ?? null) && function_exists('stobeNegTestStreamInjected')) {
        // Test switch NEG_TEST_INJECT (off by default): the model's reply with the injected fields.
        $inject = $meta['stobe_test_inject'];
        unset($meta['stobe_test_inject']);
        return stobeNegTestStreamInjected($inject,
            static fn(callable $collector) => stobeCallLLMStream($messages, $config, $collector, $meta), $onTextDelta);
    }
    unset($meta['stobe_test_inject']);
    $runtime = stobePrepareLlmRuntimeConfig($config);""")

patch("processor/chat.php",
"""            'hold_stream_on_money' => $negotiationActive && !$negotiationDefer,
""",
"""            'hold_stream_on_money' => $negotiationActive && !$negotiationDefer,
            // Test switch NEG_TEST_INJECT (off by default): forced/malformed reply fields for this turn.
            'stobe_test_inject' => (!$narratorMode && function_exists('stobeNegTestTakeInjection'))
                ? stobeNegTestTakeInjection('chat', $targetNpc, $npcData, $playerName) : null,
""")

patch("processor/bored.php",
"""        'defer_structured_stream' => is_array($negDirective),
""",
"""        'defer_structured_stream' => is_array($negDirective),
        // Test switch NEG_TEST_INJECT (off by default), context "directive".
        'stobe_test_inject' => (is_array($negDirective) && function_exists('stobeNegTestTakeInjection'))
            ? stobeNegTestTakeInjection('directive', $speakerNpc, $speakerData, $playerName) : null,
""")

E = "lib/negotiation_engine.php"
patch(E,
"""        if (!$surrenderReady && !$assistReady) return;
""",
"""        // Test switch NEG_TEST_FORCE_INITIATIVE (off by default): skips the cooldown/health gates once.
        $forcedAny = function_exists('stobeNegTestSwitchRead') ? stobeNegTestSwitchRead('NEG_TEST_FORCE_INITIATIVE') : null;
        if (!$surrenderReady && !$assistReady && $forcedAny === null) return;
""")
patch(E,
"""            if (($now - intval($recentNpc['t'] ?? 0)) < STOBE_NEG_INITIATIVE_NPC_COOLDOWN) continue;
""",
"""            $forced = $forcedAny !== null ? stobeNegTestForcedInitiative($name) : null;
            if (($now - intval($recentNpc['t'] ?? 0)) < STOBE_NEG_INITIATIVE_NPC_COOLDOWN && $forced === null) continue;
""")
patch(E,
"""            if ($surrenderReady && $hostileToPlayer && stobeNegPhaseEnabled(4) && $ratio < stobeNegCourageThreshold($personality, 0.35)) {
                stobeNegQueueDirective($name, 'surrender', '', [""",
"""            $queueAs = $forced !== null ? stobeNegTestInitiativeQueueName($forced, $name) : $name; // row 25 test switch
            if ($hostileToPlayer && stobeNegPhaseEnabled(4)
                && (($forced['kind'] ?? '') === 'surrender' || ($surrenderReady && $ratio < stobeNegCourageThreshold($personality, 0.35)))) {
                stobeNegQueueDirective($queueAs, 'surrender', '', [""")
patch(E,
"""                        . 'If you would rather fight to the end, just say so and use deal_decision NONE.',
                ], true);
                return;""",
"""                        . 'If you would rather fight to the end, just say so and use deal_decision NONE.',
                ], true);
                if ($forced !== null) stobeNegTestInitiativeFired($forced, $name, $queueAs);
                return;""")
patch(E,
"""            if ($assistReady && !$hostileToPlayer && $fightingOthers && $playerNearby && stobeNegPhaseEnabled(5)
                && !npcIsInPlayerFaction($data) && $ratio < stobeNegCourageThreshold($personality, 0.6)) {
                stobeNegQueueDirective($name, 'assist', '', [""",
"""            if (!$hostileToPlayer && $fightingOthers && $playerNearby && stobeNegPhaseEnabled(5) && !npcIsInPlayerFaction($data)
                && (($forced['kind'] ?? '') === 'assist' || ($assistReady && $ratio < stobeNegCourageThreshold($personality, 0.6)))) {
                stobeNegQueueDirective($queueAs, 'assist', '', [""")
patch(E,
"""                        . 'If you offer a deal, set deal_decision to PROPOSE with terms: player PROTECT (target npc), and your reward terms with "when":"after_player".',
                ], true);
                return;""",
"""                        . 'If you offer a deal, set deal_decision to PROPOSE with terms: player PROTECT (target npc), and your reward terms with "when":"after_player".',
                ], true);
                if ($forced !== null) stobeNegTestInitiativeFired($forced, $name, $queueAs);
                return;""")
