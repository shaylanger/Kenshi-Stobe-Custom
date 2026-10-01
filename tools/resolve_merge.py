import re

M = '/tmp/ss-merge/'
CONFLICT = re.compile(r'<<<<<<< HEAD\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n', re.S)


def resolve(path, fn):
    s = open(M + path).read()
    out, n = CONFLICT.subn(lambda m: fn(m.group(1), m.group(2)), s)
    assert '<<<<<<<' not in out and '>>>>>>>' not in out, path
    open(M + path, 'w').write(out)
    print('resolved', path, n)


# chat_helper_functions.php: command lists = ours + MOVE_TO; TTS = interaction check + prepared audio.
def chat_helper(ours, theirs):
    if "'GIVE_CATS', 'TAKE_CATS'" in ours:
        return ours.rstrip('\n') + " 'MOVE_TO', 'MOVETO',\n"
    if 'prepared_tts' in ours:
        return '                stobeInteractionRequire();\n' + ours
    raise AssertionError('unexpected chat_helper conflict')


resolve('lib/chat_helper_functions.php', chat_helper)


# data_functions.php: upstream SQL audience filtering, plus our unverified-action filter on the result.
def data_functions(ours, theirs):
    assert 'Filter before limiting' in theirs
    return """    // Filter before limiting so unrelated names cannot crowd out actual witnesses.
    // Fetch a little extra: unverified gameplay-action rows are dropped below.
    $query .= " ORDER BY COALESCE(NULLIF(localts, 0), ts, 0) DESC, ts DESC, rowid DESC LIMIT " . intval($limit + 20);
    $rows = $db->fetchAll($query, $params);
    $filtered = [];
    foreach (is_array($rows) ? $rows : [] as $row) {
        if (!is_array($row)) {
            continue;
        }
        // Older STOBE versions recorded selected gameplay bridge actions in history
        // before Kenshi confirmed they actually happened. Do not let those rows
        // override current live world state in future prompts.
        if (
            strtolower(trim(strval($row['type'] ?? ''))) === 'action'
            && function_exists('stobeActionRequiresVerifiedWorldOutcome')
        ) {
            $actionData = trim(strval($row['data'] ?? ''));
            $colon = strpos($actionData, ':');
            $actionToken = $colon === false ? $actionData : trim(substr($actionData, $colon + 1));
            if ($actionToken !== '' && stobeActionRequiresVerifiedWorldOutcome($actionToken)) {
                continue;
            }
        }
        $filtered[] = $row;
        if (count($filtered) >= $limit) {
            break;
        }
    }
    return $filtered;
"""


resolve('lib/data_functions.php', data_functions)


# dynamic profiles: upstream scheduler owns regular updates; our lifelike identity
# generation (deep identity + identity matrix) keeps running as its own background step.
def dynamic_profile(ours, theirs):
    assert 'dps_run();' in theirs and ours.startswith('function stobeMaybeRunDynamicProfileCycle(')
    identity = ours.replace('function stobeMaybeRunDynamicProfileCycle(', 'function stobeLifelikeIdentityCycle(', 1)
    old = '$regularDue = stobeDynamicProfileNpcDue($npcName, $gamets, $intervalHours);'
    assert identity.count(old) == 1
    identity = identity.replace(old, '$regularDue = false; // regular profile updates run in dynamic_profile_scheduler.php')
    return (theirs
            + '    stobeLifelikeIdentityCycle($eventType, $timestamp, $gamets, $eventData);\n}\n\n'
            + '/**\n * Lifelike identity bootstrap (deep identity text + identity matrix) for NPCs the\n'
            + ' * player actually deals with. Runs from the background manager after the\n'
            + ' * upstream profile scheduler; regular profile refreshes are left to that scheduler.\n */\n'
            + identity)


resolve('lib/dynamic_profile_helper_functions.php', dynamic_profile)


# contract test: keep both sets of assertions.
def contract_test(ours, theirs):
    return ours + theirs


resolve('tests/structured_dialogue_contract_regression.php', contract_test)

# background manager: run the identity step where the old profile cycle used to run.
p = M + 'service/manager.php'
s = open(p).read()
old = """    stobeBackgroundRecordTick($tickGamets);
    stobeBackgroundRecordTick($tickGamets);
    if (function_exists('stobeMaybeRunAutoDiaryCycle')) {"""
new = """    stobeBackgroundRecordTick($tickGamets);
    if (function_exists('stobeLifelikeIdentityCycle')) {
        stobeLifelikeIdentityCycle($tickEventType, $tickTimestamp, $tickGamets, $tickPayload);
    }
    stobeBackgroundRecordTick($tickGamets);
    if (function_exists('stobeMaybeRunAutoDiaryCycle')) {"""
assert s.count(old) == 1
open(p, 'w').write(s.replace(old, new))
print('patched service/manager.php')
