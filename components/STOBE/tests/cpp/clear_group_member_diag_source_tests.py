# NC20 source test: the ClearGroup per-member evidence loop must log why each platoon-mate is rejected, keep the
# existing gates (visible/hostile/unprotected/active/finite/pathExists==1) and not relax pathConfirmed.
# Usage: python3 clear_group_member_diag_source_tests.py <src dir>
import io, sys, re
src = sys.argv[1]
cpp = io.open(src + '/ActivityRuntimeBindings.cpp', encoding='utf-8').read()
pol = io.open(src + '/ActivityCandidatePolicy.h', encoding='utf-8').read()
fails = []
if 'ACTIVITY_CLEARGROUP_MEMBER' not in cpp: fails.append('member diag line missing')
for need in ('visible=', 'hostile=', 'protected=', 'active=', 'finite=', 'pathExists=', 'memberY=', 'dist2d=', 'now-it->second<5000'):
    if need not in cpp: fails.append('diag field/rate limit missing: ' + need)
if 'NC20ClearGroupMemberDiag(world_->navmesh,avatar' not in cpp: fails.append('diag not called from the member loop')
if 'row.pathConfirmed=nc20Raw==1;' not in cpp: fails.append('pathConfirmed must still require pathExists==1')
if not re.search(r'row\.serial && row\.visible && row\.hostile && !row\.protectedTarget && row\.active && row\.finitePosition\)\s*\{\s*nc20Raw=world_->navmesh->pathExists\(avatar,memberPosition\)', cpp):
    fails.append('path check must stay gated on all other flags with the member position')
if '!member.pathConfirmed) continue;' not in pol: fails.append('SelectClearGroupTargets must still require pathConfirmed')
if cpp.count('SelectClearGroupTargets(evidence)') != 1: fails.append('unexpected SelectClearGroupTargets call count')
print('failures=%d' % len(fails))
for f in fails: print('FAIL ' + f)
sys.exit(1 if fails else 0)
