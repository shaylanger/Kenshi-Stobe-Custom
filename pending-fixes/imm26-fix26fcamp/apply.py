#!/usr/bin/env python3
"""imm26-fix26fcamp: a camp-qualified ClearGroup resumes after save/load (row 26-f).

usage: python3 apply.py <site root> [--no-tests]      (site root = a StobeServer tree: compose, a lane site/, ...)
Server only; native unchanged. Anchor-asserted (every anchor must occur exactly once) and idempotent (a second run reports ALREADY and changes nothing).
Edits: lib/activity/ActivityResume.php, lib/activity/ActivityAgreementAdapter.php, tests/imm26_wpR1_activity_resume_regression.php.
"""
import os
import sys

MARK = 'imm26 fix26fcamp'


def edit(path, pairs):
    src = open(path, encoding='utf-8', newline='').read()
    if MARK in src:
        print('ALREADY', path)
        return
    nl = '\r\n' if '\r\n' in src else '\n'
    out = src
    for old, new in pairs:
        old = old.replace('\n', nl)
        new = new.replace('\n', nl)
        n = out.count(old)
        if n != 1:
            sys.exit('ANCHOR-FAIL %s: expected 1 occurrence, found %d of: %r' % (path, n, old[:90]))
        out = out.replace(old, new)
    open(path, 'w', encoding='utf-8', newline='').write(out)
    print('PATCHED', path)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    root = sys.argv[1]
    lib = os.path.join(root, 'lib', 'activity')
    edit(os.path.join(lib, 'ActivityResume.php'), [
        ("        if (isset($a['campZone']) && ($c['campZone'] ?? null) !== $a['campZone']) continue;\n",
         "        // imm26 fix26fcamp: the zone candidateId/scopeDigest are world+session scoped natively (new on every load), so strict equality can never match\n"
         "        // across epochs. The fixed agreedTargets above are the identity; here only 'still camp-qualified' is required, and the adapter validates and\n"
         "        // rebinds the fresh zone (a grant must carry THIS epoch's zone, the native import rejects the old one).\n"
         "        if (isset($a['campZone']) && !is_array($c['campZone'] ?? null)) continue;\n"),
        ("            'routeSelector' => ['candidateId' => strval($route['id'])]];\n}",
         "            'routeSelector' => ['candidateId' => strval($route['id'])],\n"
         "            'campZone' => isset($a['campZone']) ? ($best['campZone'] ?? null) : null];\n}"),
        ("            $accepted ? 'activity-' . bin2hex(random_bytes(16)) : strval($keep['agreement']['id']));\n    } catch (Throwable $error) {",
         "            $accepted ? 'activity-' . bin2hex(random_bytes(16)) : strval($keep['agreement']['id']), $pick['campZone'] ?? null);\n    } catch (Throwable $error) {"),
        (" * ClearGroup: the fixed target set (and camp zone) must match exactly.\n",
         " * ClearGroup: the fixed target set must match exactly; a camp-qualified one must still be camp-qualified (the fresh zone is rebound).\n"),
    ])
    edit(os.path.join(lib, 'ActivityAgreementAdapter.php'), [
        ("    public function resume(array $context, array $record, array $reference, array $routeSelector, string $newId): array\n",
         "    public function resume(array $context, array $record, array $reference, array $routeSelector, string $newId, ?array $campZone = null): array\n"),
        ("        $agreement['worldId'] = $context['worldId'];\n        if ($status === 'accepted') {\n            if (!preg_match('/\\Aactivity-",
         "        $agreement['worldId'] = $context['worldId'];\n"
         "        if (isset($agreement['campZone'])) {          // imm26 fix26fcamp: rebind to THIS epoch's zone (same validators as propose()); the digest check above used the stored one\n"
         "            if (!is_array($campZone)) { throw new \\RuntimeException('Camp zone no longer qualifies'); }\n"
         "            $this->keys($campZone, ['candidateId', 'scopeDigest']);\n"
         "            $agreement['campZone'] = ['candidateId' => $this->opaqueZoneId($campZone['candidateId'] ?? null),\n"
         "                                      'scopeDigest' => $this->sha256($campZone['scopeDigest'] ?? null)];\n"
         "        }\n"
         "        if ($status === 'accepted') {\n            if (!preg_match('/\\Aactivity-"),
    ])
    if '--no-tests' not in sys.argv:
        tp = os.path.join(root, 'tests', 'imm26_wpR1_activity_resume_regression.php')
        src = open(tp, encoding='utf-8', newline='').read()
        a = src.find("$otherZone = req(")
        endmark = "&& $obC[0]['agreement']['campZone'] === $camp && $obC[0]['agreement']['agreedTargets'] === [303, 404], $obC);"
        b = src.find(endmark)
        if MARK in src:
            print('ALREADY', tp)
        else:
            if a < 0 or b < 0 or src.count("$otherZone = req(") != 1 or src.count(endmark) != 1:
                sys.exit('ANCHOR-FAIL %s: camp block not found exactly once' % tp)
            b += len(endmark)
            new = NEW_TEST_BLOCK
            if '\r\n' in src:
                new = new.replace('\n', '\r\n')
            open(tp, 'w', encoding='utf-8', newline='').write(src[:a] + new + src[b:])
            print('PATCHED', tp)


NEW_TEST_BLOCK = r"""// imm26 fix26fcamp: zone candidateId/scopeDigest are world+session scoped natively, so the FRESH world shows a NEW zone for the same fixed targets.
$camp2 = ['candidateId'=>'v1:' . str_repeat('d', 48), 'scopeDigest'=>str_repeat('e', 64)];
$routeC = [route($C, 'local:s2:60', 'camp gate', 4000.0, 20.0, 6000.0)];
$obBefore = count(outbox(W2));
$noZone = req(W2, $C, 1112, [cand('ClearGroup', 'camp-threats', '', 303, 'activity-proposal:9:9', [303, 404], null)], $routeC);
check('camp: a fresh candidate WITHOUT a camp zone (no longer camp-qualified) is NOT resumed', chat($store, $noZone) === null && row($cg['agreement']['id'])['status'] === 'accepted' && count(outbox(W2)) === $obBefore);
foreach ([['bad candidateId', ['candidateId'=>'zone-1', 'scopeDigest'=>str_repeat('e', 64)]],
          ['bad scopeDigest', ['candidateId'=>'v1:' . str_repeat('d', 48), 'scopeDigest'=>'abc']],
          ['extra field', ['candidateId'=>'v1:' . str_repeat('d', 48), 'scopeDigest'=>str_repeat('e', 64), 'x'=>1]]] as [$why, $badZone]) {
    $mal = req(W2, $C, 1113, [cand('ClearGroup', 'camp-threats', '', 303, 'activity-proposal:9:9', [303, 404], $badZone)], $routeC);
    check("camp: a malformed fresh zone ($why) is NOT resumed and nothing is granted", chat($store, $mal) === null && row($cg['agreement']['id'])['status'] === 'accepted' && count(outbox(W2)) === $obBefore);
}
$right = req(W2, $C, 1115, [cand('ClearGroup', 'camp-threats', '', 303, 'activity-proposal:9:9', [303, 404], $camp2)], $routeC);
$cn = chat($store, $right);
$obC = array_values(array_filter(outbox(W2), static fn($x) => $x['id'] === ($cn['agreement']['id'] ?? '')));
check('camp: same targets + a NEW zone resume; the agreement is rebound to the fresh zone (not the old one), targets and scopeVersion 3 kept', is_array($cn)
    && $cn['agreement']['campZone'] === $camp2 && $cn['agreement']['campZone'] !== $camp && $cn['agreement']['agreedTargets'] === [303, 404]
    && $cn['agreement']['scopeVersion'] === 3, $cn['agreement'] ?? null);
check('camp: the new grant carries the FRESH zone (the native import rejects an old-epoch zone), targets and scopeVersion 3', count($obC) === 1
    && $obC[0]['agreement']['campZone'] === $camp2 && $obC[0]['agreement']['agreedTargets'] === [303, 404] && $obC[0]['agreement']['scopeVersion'] === 3
    && $obC[0]['scopeDigest'] === ($cn['scopeDigest'] ?? ''), $obC);
check('camp: old record superseded with continuedAs; the rebound record has a valid digest for the real cancel path', row($cg['agreement']['id'])['status'] === 'superseded'
    && (row($cg['agreement']['id'])['resume']['continuedAs'] ?? '') === ($cn['agreement']['id'] ?? '-') && cancel_ok($cn, W2, $C, 1200));"""

if __name__ == '__main__':
    main()
