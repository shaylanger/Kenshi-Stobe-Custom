#!/usr/bin/env python3
"""imm26-fix03b (row 03-b, Shay approved 2026-10-15): the NPC rumor-share hook (stobeKnowledgeShareFromSpeech) only ran on
the normal bored path (processor/bored.php). mode=director scenes (the dominant lifelike path) returned from
stobeGenerateDirectorScene() before it, so NPC-to-NPC gossip never spread in busy scenes.
Fix: new helper stobeDirectorShareRumors($turns,$actors,$gamets) in lib/imm26_knowledge.php (kill switch
STOBE_DIRECTOR_RUMOR_ENABLED, default 1; env var of the same name overrides) that loops over the scene's lines and calls the
UNCHANGED hook per NPC speaker->NPC listener line (all its gates stay: spoken text must name the subject, never to the
subject/victim, hearsay never re-spread, one row per holder+incident, player is not an NPC listener). lib/director_scene.php
calls it after the scene history is committed and the payload is out. The optional-speech gates (stobeSocialCommunicationAllowsOptional,
imm26C2AmbientQuiet) already run in bored.php BEFORE the director branch for the same turn, so a gated turn never reaches it.
Usage (WSL): python3 apply.py <tree-root>   (idempotent; anchored; CRLF-aware; installs the test)"""
import sys, os
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
TEST = 'imm26_fix03b_director_rumor_regression.php'

def load(rel):
    raw = open(os.path.join(root, rel), 'rb').read().decode('utf-8')
    return raw, ('\r\n' in raw), raw.replace('\r\n', '\n')

def save(rel, s, crlf):
    open(os.path.join(root, rel), 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode('utf-8'))

kn_rel, ds_rel = 'lib/imm26_knowledge.php', 'lib/director_scene.php'
_, kcrlf, k = load(kn_rel)
_, dcrlf, d = load(ds_rel)
if 'stobeDirectorShareRumors' in k and 'stobeDirectorShareRumors' in d:
    print('already applied')
else:
    assert 'stobeDirectorShareRumors' not in k and 'stobeDirectorShareRumors' not in d, 'half applied'
    KA = "/** Undo a belief that turned out wrong: mark it corrected and take back the opinion shift it caused. */\n"
    assert k.count(KA) == 1, 'knowledge anchor missing'
    helper = r'''/** Kill switch for rumor sharing inside director scenes (default on). Env var STOBE_DIRECTOR_RUMOR_ENABLED overrides the setting. */
function stobeDirectorRumorEnabled(): bool
{
    $v = getenv('STOBE_DIRECTOR_RUMOR_ENABLED');
    if ($v !== false && $v !== '') return !in_array(strtolower(trim($v)), ['0', 'false', 'no', 'off'], true);
    try { return !in_array(strtolower(trim(getSetting('STOBE_DIRECTOR_RUMOR_ENABLED', '1'))), ['0', 'false', 'no', 'off'], true); }
    catch (Throwable $e) { return true; }
}

/**
 * Director scenes (mode=director) return before the bored.php hook, so gossip never spread in busy scenes (row 03-b).
 * Runs the same hook per line of a committed scene: NPC speaker -> NPC listener, spoken text only.
 * $turns = scene lines (speaker, listener, text); $actors = name => getNpcData row of everyone cast in the scene.
 * @return list<array> the hearsay rows created (also logged).
 */
function stobeDirectorShareRumors(array $turns, array $actors, int $gamets): array
{
    $out = [];
    try {
        if (!stobeDirectorRumorEnabled() || !stobeKnowledgeEnabled()) return [];
        foreach ($turns as $line) {
            $speaker = strval($line['speaker'] ?? '');
            $listener = strval($line['listener'] ?? '');
            $text = strval($line['text'] ?? '');
            if ($speaker === '' || $listener === '' || $text === '' || !isset($actors[$speaker]) || !isset($actors[$listener])) continue; // player/unknown listener: not an NPC
            $shared = stobeKnowledgeShareFromSpeech($speaker, is_array($actors[$speaker]) ? $actors[$speaker] : [], $listener, $text, $gamets);
            if ($shared) {
                $out = array_merge($out, $shared);
                if (function_exists('stobeLogInfo')) stobeLogInfo('NPC gossip passed on', ['speaker' => $speaker, 'shared' => $shared, 'via' => 'director']);
            }
        }
    } catch (Throwable $e) {
        if (function_exists('stobeLogWarn')) stobeLogWarn('Director rumor share skipped', ['error' => $e->getMessage()]);
    }
    return $out;
}

'''
    k = k.replace(KA, helper + KA)
    DA = "    stobeLogInfo('Director scene queued', ['scene_id' => $scene['id'], 'turns' => count($turns)]);\n}\n"
    assert d.count(DA) == 1, 'director anchor missing'
    d = d.replace(DA, "    stobeLogInfo('Director scene queued', ['scene_id' => $scene['id'], 'turns' => count($turns)]);\n"
        "    // Row 03-b: gossip also spreads in director scenes (the same server-checked hook as bored.php; swallows Throwable).\n"
        "    require_once __DIR__ . '/imm26_knowledge.php';\n"
        "    stobeDirectorShareRumors($turns, $actors, $gamets);\n}\n")
    save(kn_rel, k, kcrlf); save(ds_rel, d, dcrlf)
    print('applied')
t = open(os.path.join(here, TEST), 'rb').read().decode('utf-8').replace('\r\n', '\n')
open(os.path.join(root, 'tests', TEST), 'wb').write((t.replace('\n', '\r\n') if kcrlf else t).encode('utf-8'))
