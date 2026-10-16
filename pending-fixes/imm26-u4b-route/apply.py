import sys
root=sys.argv[1]
def rw(path,fn):
    p=root+'/'+path; b=open(p,'rb').read().decode('utf-8'); crlf='\r\n' in b
    s=b.replace('\r\n','\n'); s2=fn(s); assert s2!=s, path
    if crlf: s2=s2.replace('\n','\r\n')
    open(p,'wb').write(s2.encode('utf-8'))
def rep(s,a,b):
    assert s.count(a)==1,(a[:70],s.count(a)); return s.replace(a,b)

def svc(s):
    # 1. hoist the per-candidate scope check so the route resolver can reuse it unchanged
    head="        $scope = static function(array $f) use ($c, $a): bool {\n"
    i=s.index(head); j=s.index("        };\n        $exact = ",i)
    body=s[i+len(head):j]
    assert s.count(head)==1
    hoisted="    $scopeOk = static function(array $c, array $a, array $f): bool {\n"+body.replace("\n            ","\n        ").replace("            return","        return",1)+"    };\n"
    s=s[:i]+"        $scope = static function(array $f) use ($c, $a, $scopeOk): bool { return $scopeOk($c, $a, $f); };\n"+s[j+len("        };\n"):]
    mark="    // imm26-u4 (rows 26-a/22-a/26-b/26-c): a Hunt target"
    s=rep(s,mark,hoisted+mark)
    s=rep(s,"use ($facts): bool {\n        $scope = static","use ($facts, $scopeOk): bool {\n        $scope = static")
    # 2. route resolver: accept-phase Hunt re-bind
    s=rep(s,"    $resolveRoute = static function(array $c, string $candidateId, ?array $expected) use ($routeCandidates): ?array {\n        foreach ($routeCandidates as $point) {",
"""    // imm26-u4b (rows 26-a/22-a/26-b/26-c): native re-emits every local route row with a new counter id each snapshot, so at ACCEPT the exact
    // stored route (id/label/coords) is gone. For a Hunt only ($accept = the agreement, set by accept()), the stored route stays valid while a
    // CURRENT native_local row of the same actor and kind lies within the resume route radius of the stored point AND of a currently grounded
    // target (same scope checks as ground()). The stored routeRef/digest are NOT rewritten. Propose, Mine, ClearGroup keep the exact rule.
    $resolveRoute = static function(array $c, string $candidateId, ?array $expected, ?array $accept = null) use ($routeCandidates, $facts, $scopeOk): ?array {
        if ($expected !== null && is_array($accept) && stobeActivityKindTargetMoves((string)($accept['kind'] ?? ''))
            && stobeActivityHuntRouteStillGrounded($c, $accept, $expected, $routeCandidates, $facts, $scopeOk)) return $expected;
        foreach ($routeCandidates as $point) {""")
    s+='''
/** True when a current native_local route row of the actor/kind is within the route radius of both the stored route point and a grounded target (imm26-u4b). */
function stobeActivityHuntRouteStillGrounded(array $c, array $agreement, array $stored, array $routeCandidates, array $facts, callable $scopeOk): bool {
    $near = static function(array $p, array $q, float $radius): bool {
        $d = 0.0;
        foreach (['x','y','z'] as $axis) { if (!is_numeric($p[$axis] ?? null) || !is_numeric($q[$axis] ?? null)) return false; $d += (floatval($p[$axis]) - floatval($q[$axis])) ** 2; }
        return sqrt($d) <= $radius;
    };
    $radius = function_exists('stobeActivityResumeSettings') ? floatval(stobeActivityResumeSettings()['route_radius'] ?? 1500) : 1500.0;
    $anchors = [];
    foreach (stobeActivitySameKindFacts($facts, $agreement) as $alt) if ($scopeOk($c, $agreement, $alt)) $anchors[] = $alt;
    if ($anchors === []) return false;
    foreach ($routeCandidates as $p) {
        if (!is_array($p) || ($p['source'] ?? '') !== 'native_local' || ($p['actor_serial'] ?? null) !== $c['actor']
            || ($p['kind'] ?? null) !== ($stored['kind'] ?? '') || !$near($p, $stored, $radius)) continue;
        foreach ($anchors as $anchor) if ($near($p, $anchor, $radius)) return true;
    }
    return false;
}
'''
    return s
rw('lib/activity/ActivityService.php',svc)

def ad(s):
    s=rep(s,"            $this->resolveRoute($context, $proposal['routeRef']['candidateId'], $proposal['routeRef']);",
            "            $this->resolveRoute($context, $proposal['routeRef']['candidateId'], $proposal['routeRef'], $proposal['agreement']);")
    s=rep(s,"    private function resolveRoute(array $context, string $candidateId, ?array $expected): array\n",
            "    private function resolveRoute(array $context, string $candidateId, ?array $expected, ?array $acceptAgreement = null): array\n")
    s=rep(s,"call_user_func($this->resolveRoute, $context, $candidateId, $expected);","call_user_func($this->resolveRoute, $context, $candidateId, $expected, $acceptAgreement);")
    return s
rw('lib/activity/ActivityAgreementAdapter.php',ad)
print('patched')
