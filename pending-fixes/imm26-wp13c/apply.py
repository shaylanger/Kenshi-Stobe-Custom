#!/usr/bin/env python3
"""imm26-wp13c (row 13-c): shared-experience record could never resolve or explain itself.
1. lib/relationship_participation.php: the native proof carries InstanceID::uid as <role>_storage_id, but chat stored core_npc.storage_id
   as hand_<serial>; the two never match, so SocialIdentity::resolve() found no row (unresolved_identity). Pass 'storage_alias' =>
   'hand_<serial>' for both parties (SocialIdentity already supports an alias: earlier storage id of the same live character).
   An EMPTY uid is still rejected as missing_identity (no hand_ fallback for the durable identity, by design).
2. A failed award left no trace. stobeParticipationAward is now a thin logging wrapper around stobeParticipationAwardEvaluate (the old body):
   every outcome writes one stobeserver.log line 'Participation award' with status + reason + proof numbers.
3. lib/relationship_experiences.php: unresolved_identity logs the resolved basis of each party.
Native proof rules (ParticipationEvidence.h) are untouched.
Usage (WSL): python3 apply.py <tree-root>   (idempotent; asserts anchors; keeps each file's EOL; installs the regression test)"""
import sys, os, shutil
root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))


def load(rel):
    s = open(os.path.join(root, rel), encoding='utf-8', newline='').read()
    crlf = '\r\n' in s
    return (s.replace('\r\n', '\n') if crlf else s), crlf


def save(rel, s, crlf):
    open(os.path.join(root, rel), 'w', encoding='utf-8', newline='').write(s.replace('\n', '\r\n') if crlf else s)


def once(s, a):
    assert s.count(a) == 1, 'anchor missing/duplicated: ' + a[:70]


P = 'lib/relationship_participation.php'
s, crlf = load(P)
if 'stobeParticipationAwardEvaluate' in s:
    print(P + ': already applied')
else:
    A1 = "/** Internal native-report boundary. Caller authenticates the report and exact owned terminal task. */\nfunction stobeParticipationAward(array $proof, array $expected): array\n{\n"
    A2 = "            'faction'=>null, 'in_player_faction'=>$role === 'partner' ? true : null, 'conscious'=>true];\n"
    for a in (A1, A2):
        once(s, a)
    wrapper = r'''/** Why a non-awarded status happened (one word); used only for the log line. */
function stobeParticipationAwardReason(string $status, array $proof, array $expected): string
{
    $n = static fn(string $k): float => is_numeric($proof[$k] ?? null) ? (float)$proof[$k] : 0.0;
    switch ($status) {
        case 'missing_identity':
            foreach (['actor', 'partner'] as $role) {
                $storage = $proof[$role . '_storage_id'] ?? null;
                if (!is_string($storage) || trim($storage) === '') return 'empty_instance_uid_' . $role;
                $name = $proof[$role . '_name'] ?? null;
                if (!is_string($name) || trim($name) === '') return 'empty_name_' . $role;
            }
            return 'bad_identity_text';
        case 'unqualified':
            return ($proof['qualified'] ?? null) === true || ($proof['qualified'] ?? null) === 'true' ? 'not_conscious_alive_or_schema' : 'participation_proof_missing_or_unqualified';
        case 'insufficient_participation':
            if ($n('qualified_samples') < 4) return 'too_few_samples';
            if ($n('last_gamets') - $n('first_gamets') < 30) return 'too_short';
            if ($n('max_separation') > 35) return 'separation';
            return 'terminal_gap_or_late';
        case 'insufficient_progress':
            return 'walked_too_little';
        default:
            return $status;
    }
}

/** Internal native-report boundary. Caller authenticates the report and exact owned terminal task.
 * Logs every outcome (stobeserver.log 'Participation award') so a failed award is never silent (imm26 13-c). */
function stobeParticipationAward(array $proof, array $expected): array
{
    $result = stobeParticipationAwardEvaluate($proof, $expected);
    try {
        $status = strval($result['status'] ?? '');
        $ok = in_array($status, ['enabled', 'shadow', 'fights', 'duplicate'], true);
        $context = ['status'=>$status, 'reason'=>$ok ? 'ok' : stobeParticipationAwardReason($status, $proof, $expected),
            'mode'=>strval($expected['mode'] ?? ''), 'agreement_id'=>strval($expected['agreement_id'] ?? ''),
            'actor_serial'=>$expected['actor_serial'] ?? null, 'partner_serial'=>$expected['partner_serial'] ?? null,
            'actor'=>substr(strval($proof['actor_name'] ?? ''), 0, 60), 'partner'=>substr(strval($proof['partner_name'] ?? ''), 0, 60),
            'actor_storage'=>substr(strval($proof['actor_storage_id'] ?? ''), 0, 60), 'partner_storage'=>substr(strval($proof['partner_storage_id'] ?? ''), 0, 60),
            'qualified_samples'=>$proof['qualified_samples'] ?? null,
            'span_gamets'=>(is_numeric($proof['last_gamets'] ?? null) && is_numeric($proof['first_gamets'] ?? null)) ? (float)$proof['last_gamets'] - (float)$proof['first_gamets'] : null,
            'max_separation'=>$proof['max_separation'] ?? null, 'actor_distance'=>$proof['actor_distance'] ?? null,
            'partner_distance'=>$proof['partner_distance'] ?? null, 'endpoint_progress'=>$proof['endpoint_progress'] ?? null];
        if ($ok && function_exists('stobeLogInfo')) stobeLogInfo('Participation award', $context);
        elseif (!$ok && function_exists('stobeLogWarn')) stobeLogWarn('Participation award', $context);
    } catch (Throwable $ignored) {
    }
    return $result;
}

/** Evaluates the native proof and records the shared experience (old body of stobeParticipationAward). */
function stobeParticipationAwardEvaluate(array $proof, array $expected): array
{
'''
    s = s.replace(A1, wrapper)
    s = s.replace(A2, "            'faction'=>null, 'in_player_faction'=>$role === 'partner' ? true : null, 'conscious'=>true,\n"
        "            // Chat stored core_npc.storage_id as hand_<serial>; the proof carries InstanceID uid. Alias lets SocialIdentity match either.\n"
        "            'storage_alias'=>'hand_' . (int)$proof[$role . '_serial']];\n")
    save(P, s, crlf)
    print(P + ': applied')

E = 'lib/relationship_experiences.php'
s, crlf = load(E)
if 'Experience identity unresolved' in s:
    print(E + ': already applied')
else:
    B = ("        if (!$a || !$b || !in_array($a['basis'], ['storage_id+name', 'storage_alias+name'], true)\n"
         "            || !in_array($b['basis'], ['storage_id+name', 'storage_alias+name'], true) || $a['id'] === $b['id']) return ['status'=>'unresolved_identity'];\n")
    once(s, B)
    new = ("        if (!$a || !$b || !in_array($a['basis'], ['storage_id+name', 'storage_alias+name'], true)\n"
           "            || !in_array($b['basis'], ['storage_id+name', 'storage_alias+name'], true) || $a['id'] === $b['id']) {\n"
           "            if (function_exists('stobeLogWarn')) stobeLogWarn('Experience identity unresolved', ['observer'=>strval($observer['name'] ?? ''), 'observer_storage'=>strval($observer['storage_id'] ?? ''),\n"
           "                'observer_basis'=>$a['basis'] ?? 'none', 'counterpart'=>strval($counterpart['name'] ?? ''), 'counterpart_storage'=>strval($counterpart['storage_id'] ?? ''),\n"
           "                'counterpart_basis'=>$b['basis'] ?? 'none', 'same_profile'=>($a && $b && $a['id'] === $b['id'])]);\n"
           "            return ['status'=>'unresolved_identity'];\n"
           "        }\n")
    s = s.replace(B, new)
    save(E, s, crlf)
    print(E + ': applied')

T = 'imm26_wp13c_participation_identity_regression.php'
os.makedirs(os.path.join(root, 'tests'), exist_ok=True)
shutil.copy(os.path.join(here, T), os.path.join(root, 'tests', T))
print('test installed')
