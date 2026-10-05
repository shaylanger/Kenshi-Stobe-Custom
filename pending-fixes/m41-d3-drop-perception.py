# Shay D3 (2026-10-05): drop Perception from PG gear. Usage: python3 m41-d3-drop-perception.py <PG repo root>
import sys,os
root=sys.argv[1]
def patch(rel,pairs):
    p=os.path.join(root,rel); s=open(p,encoding='utf-8',newline='').read()
    for a,b in pairs:
        assert s.count(a)==1,(rel,a); s=s.replace(a,b)
    open(p,'w',encoding='utf-8',newline='').write(s)
patch('src/ProfessionGearCore.h',[('bool IsProfessionStat(ProfessionStat stat);',
 'bool IsProfessionStat(ProfessionStat stat);\n'
 '// Retired stats never roll and give no bonus or tooltip line even on old records (Perception: game 1.0.65\n'
 '// detection never reads it, row 199 / Shay D3).\n'
 'bool StatRetired(ProfessionStat stat);')])
patch('src/ProfessionGearCore.cpp',[
 ('case TAG_BOOTS_TRAVEL: case TAG_SCOUT_GEAR: AddStat(out,STAT_ATHLETICS); AddStat(out,STAT_PERCEPTION); break;',
  'case TAG_BOOTS_TRAVEL: case TAG_SCOUT_GEAR: AddStat(out,STAT_ATHLETICS); break;'),
 ('case TAG_TURRET_GEAR: AddStat(out,STAT_TURRETS); AddStat(out,STAT_PERCEPTION); break;',
  'case TAG_TURRET_GEAR: AddStat(out,STAT_TURRETS); break;'),
 ('        AddStat(out,STAT_PERCEPTION); AddStat(out,STAT_SCIENCE); AddStat(out,STAT_ENGINEERING);',
  '        AddStat(out,STAT_SCIENCE); AddStat(out,STAT_ENGINEERING);'),
 ('std::vector<ProfessionStat> AllowedStats(const std::vector<ItemTag>& tags) {',
  'bool StatRetired(ProfessionStat stat) { return stat==STAT_PERCEPTION; }\n\n'
  'std::vector<ProfessionStat> AllowedStats(const std::vector<ItemTag>& tags) {'),
])
patch('src/ProfessionGearPlugin.cpp',[
 ('    for(size_t j=0;j<it->second.affixes.size();++j)\n      totals[it->second.affixes[j].stat]+=it->second.affixes[j].percent;',
  '    for(size_t j=0;j<it->second.affixes.size();++j)\n      if(!PGP::StatRetired(it->second.affixes[j].stat))\n        totals[it->second.affixes[j].stat]+=it->second.affixes[j].percent;'),
 ('''    lines.push_back(StringPair("Profession Gear",""));
    for(size_t j=0;j<it->second.affixes.size();++j){
      std::ostringstream s;''',
  '''    bool header=false;
    for(size_t j=0;j<it->second.affixes.size();++j){
      if(PGP::StatRetired(it->second.affixes[j].stat)) continue;
      if(!header){ lines.push_back(StringPair("Profession Gear","")); header=true; }
      std::ostringstream s;'''),
 ('    if(std::find(pool.begin(),pool.end(),a.stat)==pool.end()) problems+=" illegal_stat("',
  '    if(PGP::StatRetired(a.stat)) continue;  // old record, inert by design\n'
  '    if(std::find(pool.begin(),pool.end(),a.stat)==pool.end()) problems+=" illegal_stat("'),
])
patch('tests/test_profession_gear.cpp',[
 ('Check(HasStat(x,STAT_PERCEPTION)&&HasStat(x,STAT_SCIENCE)&&HasStat(x,STAT_ENGINEERING)&&HasStat(x,STAT_ROBOTICS)&&HasStat(x,STAT_TURRETS),"goggles multi-context pool");}',
  'Check(!HasStat(x,STAT_PERCEPTION)&&HasStat(x,STAT_SCIENCE)&&HasStat(x,STAT_ENGINEERING)&&HasStat(x,STAT_ROBOTICS)&&HasStat(x,STAT_TURRETS),"goggles multi-context pool, no Perception");}'),
 ('Check(HasStat(s,STAT_ATHLETICS)&&HasStat(s,STAT_PERCEPTION),"travel stat pool");}',
  'Check(HasStat(s,STAT_ATHLETICS)&&!HasStat(s,STAT_PERCEPTION),"travel stat pool, no Perception");}\n'
  '  Check(StatRetired(STAT_PERCEPTION)&&!StatRetired(STAT_ATHLETICS),"Perception retired");\n'
  '  {for(int t=0;t<=TAG_GOGGLES_GENERIC;++t){std::vector<ItemTag> one(1,(ItemTag)t);Check(!HasStat(AllowedStats(one),STAT_PERCEPTION),"no pool rolls Perception");}}'),
])
print("OK")
