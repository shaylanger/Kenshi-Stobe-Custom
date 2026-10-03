#include "SocialEventProtocol.h"
#include <sstream>
namespace StobeSocial {
namespace {
std::string Escape(const std::string& s) {
    std::string out; const char* hex="0123456789abcdef";
    for(size_t i=0;i<s.size();++i) {
        unsigned char c=s[i];
        if(c=='"'||c=='\\'){out+='\\';out+=c;}
        else if(c<32){out+="\\u00";out+=hex[c>>4];out+=hex[c&15];}
        else out+=c;
    }
    return out;
}
bool Id(const std::string& s) {
    if(s.empty()||s.size()>128)return false;
    for(size_t i=0;i<s.size();++i) {
        char c=s[i]; if(!((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='.'||c==':'||c=='-'))return false;
    }
    return true;
}
std::string Entity(unsigned int serial,const std::string& name,const std::string& session,unsigned long epoch) {
    if(!serial)return "null";
    std::ostringstream s;
    // Opaque session/load-local identity. NEVER a persistent relationship binding.
    s<<"{\"entity_key\":\""<<Escape(session)<<":"<<epoch<<":"<<serial
      <<"\",\"serial\":"<<serial<<",\"name\":\""<<Escape(name)<<"\"}";
    return s.str();
}
}
bool SupportedKind(const std::string& kind) {
    const char* kinds[]={"combat","combat_start","combat_end","major_damage","knockout","recovered","death","limb_loss","healing","slavery","imprisonment","carry","looting","item_pickup","trade","eat","predation","dialogue"};
    for(size_t i=0;i<sizeof(kinds)/sizeof(kinds[0]);++i)if(kind==kinds[i])return true;
    return false;
}
std::string Envelope(const std::string& campaign,const std::string& session,unsigned long epoch,unsigned long sequence,long long gameTs,
 const std::string& kind,unsigned int actorSerial,const std::string& actorName,unsigned int targetSerial,const std::string& targetName,const std::string& message) {
    if(!Id(campaign)||!Id(session)||session.size()>64||!epoch||!sequence||gameTs<0||!SupportedKind(kind)||actorName.size()>180||targetName.size()>180||message.size()>4096)return "";
    std::ostringstream id; id<<session<<":"<<epoch<<":"<<sequence;
    std::ostringstream out;
    out<<"{\"schema_version\":1,\"campaign_id\":\""<<campaign<<"\",\"native_session_id\":\""<<session
       <<"\",\"timeline_epoch\":\""<<epoch<<"\",\"event_id\":\""<<id.str()<<"\",\"incident_id\":\""<<id.str()
       <<"\",\"sequence\":"<<sequence<<",\"game_ts\":"<<gameTs<<",\"event_kind\":\""<<kind<<"\",\"origin\":\"gameplay\",\"actor\":"
       <<Entity(actorSerial,actorName,session,epoch)<<",\"target\":"<<Entity(targetSerial,targetName,session,epoch)
       <<",\"state_before\":{},\"state_after\":{},\"witnesses\":[],\"facts\":{\"message\":\""<<Escape(message)<<"\"}}";
    return out.str();
}
}

namespace StobeSocial {
bool StructuredKind(const std::string& kind) {
    const char* kinds[]={"attack","harm","recovered","item_transfer","enslaved","freed","aid","carry_start","carry_end","placed","eat","trade"};
    for(size_t i=0;i<sizeof(kinds)/sizeof(kinds[0]);++i)if(kind==kinds[i])return true;
    return false;
}
std::string JsonString(const std::string& value){return "\""+Escape(value)+"\"";}
std::string JsonBool(int triState){return triState<0?"null":(triState?"true":"false");}
std::string JsonCountMap(const std::map<std::string,int>& counts,size_t cap){
    std::ostringstream out; out<<"{"; size_t n=0;
    for(std::map<std::string,int>::const_iterator it=counts.begin();it!=counts.end()&&n<cap;++it){
        if(it->second<=0||it->first.empty()||it->first.size()>160)continue;
        out<<(n?",":"")<<JsonString(it->first)<<":"<<it->second; ++n;
    }
    out<<"}"; return out.str();
}
namespace {
std::string StructuredEntity(const EntityInfo* e,const std::string& session,unsigned long epoch){
    if(!e||!e->serial||e->name.size()>180)return "null";
    std::ostringstream s;
    // entity_key stays session/load-local; storage_id (instance UID or hand_<serial>) helps the server bind a profile.
    s<<"{\"entity_key\":\""<<Escape(session)<<":"<<epoch<<":"<<e->serial<<"\",\"serial\":"<<e->serial
     <<",\"name\":"<<JsonString(e->name)
     <<",\"storage_id\":"<<(e->storageId.empty()||e->storageId.size()>128?"null":JsonString(e->storageId))
     <<",\"faction\":"<<(e->faction.empty()||e->faction.size()>128?"null":JsonString(e->faction))
     <<",\"in_player_faction\":"<<JsonBool(e->inPlayerFaction)
     <<",\"conscious\":"<<JsonBool(e->conscious)<<"}";
    return s.str();
}
}
std::string StructuredEnvelope(const std::string& campaign,const std::string& session,unsigned long epoch,unsigned long sequence,
 long long gameTs,const std::string& kind,const EntityInfo* actor,const EntityInfo* target,const std::string& factsBody){
    if(!Id(campaign)||!Id(session)||session.size()>64||!epoch||!sequence||gameTs<0||!StructuredKind(kind)||factsBody.size()>32768)return "";
    if(!factsBody.empty()&&(factsBody[0]!='"'))return "";
    std::ostringstream id; id<<session<<":"<<epoch<<":"<<sequence;
    std::ostringstream out;
    out<<"{\"schema_version\":1,\"campaign_id\":\""<<campaign<<"\",\"native_session_id\":\""<<session
       <<"\",\"timeline_epoch\":\""<<epoch<<"\",\"event_id\":\""<<id.str()<<"\",\"incident_id\":\""<<id.str()
       <<"\",\"sequence\":"<<sequence<<",\"game_ts\":"<<gameTs<<",\"event_kind\":\""<<kind<<"\",\"origin\":\"gameplay\",\"actor\":"
       <<StructuredEntity(actor,session,epoch)<<",\"target\":"<<StructuredEntity(target,session,epoch)
       <<",\"state_before\":{},\"state_after\":{},\"witnesses\":[],\"facts\":{\"source\":\"structured\""
       <<(factsBody.empty()?"":",")<<factsBody<<"}}";
    return out.str();
}
}
