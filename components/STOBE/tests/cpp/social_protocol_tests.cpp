#include "SocialEventProtocol.h"
#include <iostream>
#include <stdexcept>
#include <string>
static void check(bool ok,const char* what){if(!ok)throw std::runtime_error(what);}
static std::string Structured(){
    StobeSocial::EntityInfo a,b;
    a.serial=11;a.name="Shay";a.storageId="hand_11";a.faction="Nameless";a.inPlayerFaction=1;a.conscious=1;
    b.serial=22;b.name="Vorl [Dust \"Bandit\"]";b.faction="Dust Bandits";b.inPlayerFaction=0;b.conscious=-1;
    std::map<std::string,int> inv; inv["Dried Meat"]=3; inv["bad"]=0;
    return StobeSocial::StructuredEnvelope("campaign","session",2,5,300,"attack",&a,&b,
        "\"victim_targeting_actor\":"+StobeSocial::JsonBool(0)+",\"inventory\":"+StobeSocial::JsonCountMap(inv,64));
}
int main(int argc,char** argv){
    std::string s=StobeSocial::Envelope("campaign","session",1,1,100,"combat",1,"A",2,"B","quote\"\n");
    check(!s.empty(),"valid envelope");
    check(s==StobeSocial::Envelope("campaign","session",1,1,100,"combat",1,"A",2,"B","quote\"\n"),"retry payload stable");
    check(s!=StobeSocial::Envelope("campaign","session",2,1,100,"combat",1,"A",2,"B","quote\"\n"),"load namespaces identity");
    check(s.find("quote\\\"\\u000a")!=std::string::npos,"JSON escaping");
    check(StobeSocial::Envelope("","session",1,1,100,"combat",1,"A",2,"B","x").empty(),"missing campaign");
    check(StobeSocial::Envelope("campaign","session",1,1,100,"unknown",1,"A",2,"B","x").empty(),"unknown kind");
    check(StobeSocial::Envelope("campaign","session",1,1,-1,"combat",1,"A",2,"B","x").empty(),"negative time");
    check(StobeSocial::Envelope("campaign","session",1,1,100,"combat",0,"",0,"","x").find("\"actor\":null")!=std::string::npos,"unknown actor preserved");
    // Structured (REL phase 2+)
    std::string t=Structured();
    check(!t.empty(),"structured envelope");
    check(t==Structured(),"structured retry stable");
    check(t.find("\"source\":\"structured\"")!=std::string::npos,"structured source tag");
    check(t.find("\"conscious\":null")!=std::string::npos,"unknown consciousness stays null");
    check(t.find("\"in_player_faction\":true")!=std::string::npos,"tri-state true");
    check(t.find("\"bad\"")==std::string::npos,"zero counts dropped");
    check(t.find("Vorl [Dust \\\"Bandit\\\"]")!=std::string::npos,"structured name escaping");
    {
        StobeSocial::EntityInfo x; x.serial=9; x.name="Rel Xan"; x.storageId="hand_9";
        std::string plain=StobeSocial::StructuredEnvelope("campaign","session",2,6,300,"freed",nullptr,&x,"");
        check(plain.find("storage_alias")==std::string::npos,"no alias unless the handle changed");
        x.storageAlias="hand_7";
        std::string aliased=StobeSocial::StructuredEnvelope("campaign","session",2,6,300,"freed",nullptr,&x,"");
        check(aliased.find("\"storage_id\":\"hand_9\",\"storage_alias\":\"hand_7\"")!=std::string::npos,"re-squad alias sent");
    }
    check(StobeSocial::StructuredEnvelope("campaign","session",2,5,300,"combat",nullptr,nullptr,"").empty(),"legacy kind not structured");
    check(StobeSocial::StructuredEnvelope("campaign","session",2,5,300,"harm",nullptr,nullptr,"{}").empty(),"facts body must be pairs");
    check(StobeSocial::StructuredEnvelope("campaign","session",2,5,300,"harm",nullptr,nullptr,"").find("\"actor\":null")!=std::string::npos,"unknown attacker null");
    StobeSocial::EntityInfo w; w.serial=33; w.name="Witness"; w.conscious=1;
    std::string wj=StobeSocial::WitnessJson(w,"session",2,true,true,1,-1,0);
    check(wj.find("\"perceived\":true")!=std::string::npos&&wj.find("\"sees_target\":null")!=std::string::npos,"witness entry tri-state");
    std::string tw=StobeSocial::StructuredEnvelope("campaign","session",2,6,300,"harm",nullptr,nullptr,"","["+wj+"]");
    check(tw.find("\"witnesses\":[{\"entity\"")!=std::string::npos,"witnesses in envelope");
    check(StobeSocial::StructuredEnvelope("campaign","session",2,6,300,"harm",nullptr,nullptr,"","{}").empty(),"witnesses must be an array");
    StobeSocial::EntityInfo none; check(StobeSocial::WitnessJson(none,"session",2,true,true,1,1,1).empty(),"witness needs an entity");
    if(argc>1&&std::string(argv[1])=="--emit-structured")std::cout<<t;
    else if(argc>1)std::cout<<s; else std::cout<<"22 native contract checks passed\n";
}
