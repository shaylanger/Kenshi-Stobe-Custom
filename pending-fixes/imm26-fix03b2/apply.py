#!/usr/bin/env python3
"""imm26-fix03b2 (row 03-b / 22-b): lib/director_scene.php accepted only `Name|<digits>` people entries, but main.php annotates
CACHE_PEOPLE through normalizeStorageIdToken, so every entry reaches the Director as `Name|hand_<serial>` (negative signed serials
become unsigned hand_ too). ctype_digit() rejected all of them: $identities empty -> 'No eligible Director cast' on every director tick.
Fix: new pure helper stobeDirectorPeopleSerials() accepts `Name|<digits>` and `Name|hand_<digits>`, hands the DLL the digits-only
actor_id it validates (ChatBox.cpp ~3644: digits only and `speaker|serial` must appear verbatim in the request's own people list), and
skips a name whose raw client serial is not digits (negative signed serial: the DLL would cancel the whole scene). The kill switch
STOBE_DIRECTOR_RUMOR_ENABLED (fix03b, lib/imm26_knowledge.php) is untouched.
Usage (WSL): python3 apply.py <tree-root>   (idempotent; anchored; CRLF-aware; installs the test)"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
TEST = 'imm26_fix03b2_director_identity.php'
rel = 'lib/director_scene.php'
raw = open(os.path.join(root, rel), 'rb').read().decode('utf-8')
crlf = '\r\n' in raw
d = raw.replace('\r\n', '\n')
if 'stobeDirectorPeopleSerials' in d:
    print('already applied')
else:
    A1 = "// Author all dialogue and prepare its audio before emitting a single scene payload.\nfunction stobeGenerateDirectorScene("
    assert d.count(A1) == 1, 'anchor 1 missing'
    A2 = """    $identities = [];
    foreach (json_decode(strval($GLOBALS['CACHE_PEOPLE'] ?? $_GET['people'] ?? '[]'), true) ?: [] as $participant) {
        if (!is_string($participant)) continue;
        $parts = explode('|', $participant, 2);
        if (count($parts) === 2 && ctype_digit($parts[1])) $identities[$parts[0]] = $parts[1];
    }
"""
    assert d.count(A2) == 1, 'anchor 2 missing'
    helper = r'''/**
 * Name => digits-only serial for the Director cast. CACHE_PEOPLE is annotated by main.php (normalizeStorageIdToken), so entries are
 * `Name|hand_<serial>` (plain `Name|<serial>` is still accepted). The DLL validates actor_id as digits only, bound to the
 * `speaker|serial` token of its own request, so the hand_ prefix is stripped. When $rawPeopleJson (the client's original list) is
 * given, a name whose raw serial is not digits (negative signed serial) is skipped: the DLL would cancel the whole scene for it.
 */
function stobeDirectorPeopleSerials(string $peopleJson, string $rawPeopleJson = ''): array
{
    $rawSerial = [];
    foreach (json_decode($rawPeopleJson, true) ?: [] as $entry) {
        if (!is_string($entry)) continue;
        $pair = explode('|', $entry, 2);
        if (count($pair) === 2) $rawSerial[$pair[0]] = $pair[1];
    }
    $identities = [];
    foreach (json_decode($peopleJson, true) ?: [] as $participant) {
        if (!is_string($participant)) continue;
        $parts = explode('|', $participant, 2);
        if (count($parts) !== 2 || preg_match('/^(?:hand_)?(\d+)$/i', $parts[1], $m) !== 1) continue;
        if (isset($rawSerial[$parts[0]]) && !ctype_digit($rawSerial[$parts[0]])) continue;
        $identities[$parts[0]] = $m[1];
    }
    return $identities;
}

'''
    d = d.replace(A1, helper + A1)
    d = d.replace(A2, "    $identities = stobeDirectorPeopleSerials(strval($GLOBALS['CACHE_PEOPLE'] ?? $_GET['people'] ?? '[]'), strval($_GET['people'] ?? ''));\n")
    open(os.path.join(root, rel), 'wb').write((d.replace('\n', '\r\n') if crlf else d).encode('utf-8'))
    print('applied')
os.makedirs(os.path.join(root, 'tests'), exist_ok=True)
shutil.copyfile(os.path.join(here, TEST), os.path.join(root, 'tests', TEST))
