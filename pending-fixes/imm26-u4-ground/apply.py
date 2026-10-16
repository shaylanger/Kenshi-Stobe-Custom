import sys,re
root=sys.argv[1]
def rw(path,fn):
    p=root+'/'+path; b=open(p,'rb').read().decode('utf-8'); crlf='\r\n' in b
    s=b.replace('\r\n','\n'); s2=fn(s); assert s2!=s, path
    if crlf: s2=s2.replace('\n','\r\n')
    open(p,'wb').write(s2.encode('utf-8'))
def rep(s,a,b):
    assert s.count(a)==1,(a[:60],s.count(a)); return s.replace(a,b)

# ---- ActivityService.php: resolve closure
def svc(s):
    old_start=s.index("    $resolve = static function(array $c, array $a, array $ref) use ($facts): bool {")
    old_end=s.index("    $policy = static function")
    new='''    // imm26-u4 (rows 26-a/22-a/26-b/26-c): a Hunt target is an animal that wanders, flees or dies between the offer and the answer,
    // and the native side only keeps a candidate id while that exact animal is still emitted. At ACCEPT (phase 'accept', Hunt only) the
    // stored discoveryRef may therefore be satisfied by ANY currently observed candidate of the same kind/source/resource that passes every
    // other check (suitable, permitted, reachable, observedNow, not protected, no conflicting order). The stored record and its digest are
    // NOT rebound (the native consent/report path matches that digest). Propose, resume, Mine and ClearGroup keep the exact-ref rule.
    $resolve = static function(array $c, array $a, array $ref, string $phase='propose') use ($facts): bool {
        $scope = static function(array $f) use ($c, $a): bool {
            return ($f['worldId'] ?? null) === $c['worldId'] && ($f['actor'] ?? null) === $c['actor']
                && ($f['sourceId'] ?? null) === $a['sourceId'] && ($f['resourceId'] ?? '') === $a['resourceId']
                && ($f['kind'] ?? '') === $a['kind'] && ($f['pathReachable'] ?? false) === true
                && ($f['observedNow'] ?? false) === true && ($f['suitable'] ?? false) === true
                && ($f['activityPermitted'] ?? false) === true && ($f['protectedTarget'] ?? true) === false
                && ($f['conflictingOrder'] ?? true) === false
                && ($a['kind'] !== 'ClearGroup' || ($f['agreedTargets'] ?? []) === $a['agreedTargets'])
                && (!isset($a['campZone']) || (($f['campZone'] ?? null) === $a['campZone']));
        };
        $exact = stobeActivitySelectFacts($facts,$a,$ref);
        if (($exact['candidateId'] ?? null) === $ref['candidateId'] && ($exact['targetSerial'] ?? null) === $ref['targetSerial'] && $scope($exact)) return true;
        if ($phase !== 'accept' || !stobeActivityKindTargetMoves((string)$a['kind'])) return false;
        foreach (stobeActivitySameKindFacts($facts,$a) as $alt) if ($scope($alt)) return true;
        return false;
    };
'''
    s=s[:old_start]+new+s[old_end:]
    s+='''
/** Kinds whose native target is a living animal that may leave view between offer and acceptance (imm26-u4). */
function stobeActivityKindTargetMoves(string $kind): bool { return $kind === 'Hunt'; }

/** Every current candidate of the agreement's kind/source/resource, merged with the authenticated top-level fields (imm26-u4). */
function stobeActivitySameKindFacts(array $facts,array $agreement): array {
    $out = [];
    foreach (($facts['candidates'] ?? []) as $candidate) {
        if (!is_array($candidate) || ($candidate['sourceId'] ?? null) !== $agreement['sourceId'] || ($candidate['resourceId'] ?? '') !== $agreement['resourceId']
            || ($candidate['kind'] ?? '') !== $agreement['kind']) continue;
        $out[] = array_merge($candidate,array_intersect_key($facts,array_flip(['worldId','actor','requester','npcWilling'])));
    }
    return $out;
}
'''
    return s
rw('lib/activity/ActivityService.php',svc)

# ---- Adapter: pass phase
def ad(s):
    s=rep(s,"        $this->authorize('accept', $context, $proposal['agreement']);\n        $this->ground($context, $proposal['agreement'], $proposal['discoveryRef']);",
            "        $this->authorize('accept', $context, $proposal['agreement']);\n        $this->ground($context, $proposal['agreement'], $proposal['discoveryRef'], 'accept');")
    s=rep(s,"    private function ground(array $context, array $agreement, array $reference): void\n    {",
            "    private function ground(array $context, array $agreement, array $reference, string $phase = 'propose'): void\n    {")
    s=rep(s,"call_user_func($this->resolve, $context, $agreement, $reference) !== true","call_user_func($this->resolve, $context, $agreement, $reference, $phase) !== true")
    return s
rw('lib/activity/ActivityAgreementAdapter.php',ad)

# ---- Chat: log rejections (diag, informational)
def chat(s):
    return rep(s,"        $actions = [];\n        $reason=$error->getMessage();\n",
"""        $actions = [];
        $reason=$error->getMessage();
        // imm26-u4: the reason was invisible in every log (rows 26-a..c needed a lane-only hack to see it).
        if (function_exists('stobeLogWarn')) stobeLogWarn('Activity decision rejected',['decision'=>$decision,'reason'=>$reason,
            'intent'=>$decision==='PROPOSE' ? substr(strval($reply['activity_intent'] ?? ''),0,400) : null]);
""")
rw('lib/activity/ActivityChat.php',chat)
print('patched')
