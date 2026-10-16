p='/mnt/c/KenshiTestRuns/imm26-nc10/tests/activity_wild_verdict_tests.cpp'
s=open(p).read()
a='f=Wild(); f.homeBuilding=true; Expect("home building",f,"animal_not_wild_ownership");'
assert s.count(a)==1
s=s.replace(a,
 'f=Wild(); f.homeBuilding=true; Expect("home building alone (NC10: roaming wild herds always have it)",f,"");\n f=Wild(); f.homeBuilding=true; f.homeTown=true; Expect("home building + home town still owned",f,"animal_not_wild_ownership");\n f=Wild(); f.homeBuilding=true; f.factionNotReal=false; Expect("home building does not rescue a real faction",f,"animal_not_wild_real_faction");\n f=Wild(); f.homeBuilding=true; f.trader=true; Expect("home building does not rescue a trader",f,"animal_not_wild_squad_type");')
s=s.replace('NC9-WILD-TESTS','NC10-WILD-TESTS').replace('NC8 verdict clauses unchanged + Flags','NC8 clauses, homeBuilding no longer ownership, Flags')
open(p,'w').write(s)
