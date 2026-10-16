import sys
p=sys.argv[1]
s=open(p,encoding='utf-8',newline='').read()
a1="    $db=$GLOBALS['db'];$locked=false;$topicLocked=false;$tx=null;$lockKey=stobeFollowupPrefix($scope);\n    try {"
b1="    $db=$GLOBALS['db'];$locked=false;$topicLocked=false;$tx=null;$lockKey=stobeFollowupPrefix($scope);$imm26Retired=0;\n    try {"
a2="            if ($imm26Resolved) imm26C2RetireResolved($scope,$now,$imm26Records,$imm26Resolved);"
b2="            if ($imm26Resolved) $imm26Retired=imm26C2RetireResolved($scope,$now,$imm26Records,$imm26Resolved);"
a3="            stobeFollowupFinish($tx,true);$tx=null;return $record;\n        }\n    } catch (Throwable $e) { return null; }"
b3="            stobeFollowupFinish($tx,true);$tx=null;return $record;\n        }\n        if ($imm26Retired>0) { stobeFollowupFinish($tx,true);$tx=null; }\n        return null;\n    } catch (Throwable $e) { return null; }"
for a,b in((a1,b1),(a2,b2),(a3,b3)):
    assert s.count(a)==1,a
    s=s.replace(a,b)
open(p,'w',encoding='utf-8',newline='').write(s)
print('ok',p)
