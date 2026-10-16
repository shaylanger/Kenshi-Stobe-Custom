# NC15 = NC14 + camp town identity keyed on GameData sid when the TownBase handle serial is 0 (row 14-c).
# Usage: python3 nc15edit.py <NC14-tree-root>   (root contains src/); edits src/ActivityCampNativeAdapter.h and src/ActivityCampTownReader.cpp only.
import sys,io
root=sys.argv[1]
def edit(path,old,new,count=1):
    p=root+'/'+path
    s=io.open(p,'r',encoding='utf-8',newline='').read()
    if '\r\n' in s:
        old=old.replace('\n','\r\n'); new=new.replace('\n','\r\n')
    assert s.count(old)==count,(path,old[:60],s.count(old))
    s=s.replace(old,new)
    io.open(p,'w',encoding='utf-8',newline='').write(s)
H='src/ActivityCampNativeAdapter.h'
R='src/ActivityCampTownReader.cpp'
# 1. header: SidKey helper + ValidFacts no longer needs a nonzero handle serial
edit(H,'''inline bool ValidFacts(const TownBaseFacts& f) {
  return f.runtimeSerial != 0 && f.handleSerial != 0 &&
    f.runtimeSerial == f.handleSerial && !f.gameDataSid.empty() &&
''','''// NC15 (row 14-c): TownBase handle serial is 0 for every TownList entry (ACTIVITY_CAMP_TOWNS_DIAG
// handle_serial_zero:378). Identity is then a nonzero FNV-1a 64 key over the GameData string id plus the
// rounded position (two towns may share a sid). Handle fields stay informational.
inline unsigned long long SidKey(const std::string& sid, float x, float z) {
  std::ostringstream s;
  s.imbue(std::locale::classic());
  s << sid << '@' << static_cast<long long>(std::floor(x + 0.5f)) << ',' << static_cast<long long>(std::floor(z + 0.5f));
  const std::string k = s.str();
  unsigned long long h = 14695981039346656037ULL;
  for (std::size_t i = 0; i < k.size(); ++i) { h ^= static_cast<unsigned char>(k[i]); h *= 1099511628211ULL; }
  return h ? h : 1ULL;
}
inline bool ValidFacts(const TownBaseFacts& f) {
  return f.runtimeSerial != 0 &&
    (f.handleSerial == 0 || f.runtimeSerial == f.handleSerial) && !f.gameDataSid.empty() &&
''')
# 2. reader ReadFacts: fall back to the sid key when the handle serial is 0
edit(R,'''    facts.radius=town->_NV_getRadius();
    if (!ValidFacts(facts)) return false;
''','''    facts.radius=town->_NV_getRadius();
    if (facts.runtimeSerial==0 && Finite(facts.x) && Finite(facts.z)) // NC15 sid-keyed identity
      facts.runtimeSerial=SidKey(facts.gameDataSid,facts.x,facts.z);
    if (!ValidFacts(facts)) return false;
''')
# 3. reader ExplainFacts (diag mirror of ReadFacts)
edit(R,'''    if (facts->runtimeSerial == 0) return "handle_serial_zero";
''','')
edit(R,'''    if (facts->radius < 25.0f || facts->radius > 2000.0f) return "radius_out_of_range";
    return "ok";
''','''    if (facts->radius < 25.0f || facts->radius > 2000.0f) return "radius_out_of_range";
    if (facts->runtimeSerial == 0) { // NC15: sid-keyed identity (handle serial is 0)
      facts->runtimeSerial = SidKey(facts->gameDataSid, facts->x, facts->z);
      return "ok_sid_keyed";
    }
    return "ok";
''')
edit(R,'''o << "ACTIVITY_CAMP_TOWNS_DIAG raw=" << entries.size() << " accepted=" << accepted << " types=";''',
 '''o << "ACTIVITY_CAMP_TOWNS_DIAG raw=" << entries.size() << " accepted=" << accepted << " nc15=sid_key types=";''')
