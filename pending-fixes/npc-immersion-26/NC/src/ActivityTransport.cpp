#include "ActivityTransport.h"
#include "ActivityController.h"
#include "../legacy-v1/ActivityController.h"
#include "ActivityGoals.h"
#include "ActivityDiscoveryRef.h"
#include "Comm.h"
#include "Interaction.h"
#include "PlaythroughSession.h"
#include "StobeText.h"
#include <windows.h>
#include <winhttp.h>
#include <wincrypt.h>
#include <boost/property_tree/ptree.hpp>
#include <boost/property_tree/json_parser.hpp>
#include <algorithm>
#include <deque>
#include <float.h>
#include <ctime>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <vector>
#pragma comment(lib,"winhttp.lib")
#pragma comment(lib,"advapi32.lib")
namespace Stobe { namespace Activity {
namespace {
typedef boost::property_tree::ptree Tree;
bool HasField(const Tree& tree,const char* key) { return tree.get_child_optional(key).is_initialized(); }
struct Turn {
 std::string id,world,text,facts,consent,ticket;
 unsigned actor,requester; Clock now; unsigned long epoch;
 Turn():actor(0),requester(0),now(0),epoch(0) {}
};
struct Offer { Tree record; std::string world; unsigned actor,requester; Offer():actor(0),requester(0){} };
struct PendingEvent { std::string agreementId,json; unsigned actor,requester; Clock now; DWORD queuedTick; unsigned attempts; PendingEvent():actor(0),requester(0),now(0),queuedTick(0),attempts(0){} };
struct State {
 CRITICAL_SECTION mutex; std::map<std::string,Turn> turns; std::deque<PendingEvent> events;
 std::map<std::string,Offer> displayed; std::map<std::string,unsigned> revisions,reported;
 std::map<std::string,Tree> receipts;
 std::vector<unsigned long long> acknowledgements;
 std::string world; Clock now; DWORD lastPoll; bool polling;
 State():now(0),lastPoll(0),polling(false) { InitializeCriticalSection(&mutex); }
};
BOOL CALLBACK InitState(PINIT_ONCE,PVOID,PVOID* p) { *p=new State; return TRUE; }
State& S() { static INIT_ONCE once=INIT_ONCE_STATIC_INIT; PVOID p=NULL; InitOnceExecuteOnce(&once,InitState,NULL,&p); return *static_cast<State*>(p); }
struct Lock { Lock(){EnterCriticalSection(&S().mutex);} ~Lock(){LeaveCriticalSection(&S().mutex);} };
std::string Escape(const std::string& s) { return Text::EscapeJSON(s); }
std::string Hex(const unsigned char* data,size_t count) {
 const char* hex="0123456789abcdef";std::string result;
 for(size_t i=0;i<count;++i){result+=hex[data[i]>>4];result+=hex[data[i]&15];}return result;
}
bool HexId(const std::string& s,size_t length) { return s.size()==length && s.find_first_not_of("0123456789abcdef")==std::string::npos; }
std::string Nonce() {
 HCRYPTPROV p=0;BYTE bytes[16];
 if(!CryptAcquireContext(&p,NULL,NULL,PROV_RSA_AES,CRYPT_VERIFYCONTEXT)) return "";
 BOOL ok=CryptGenRandom(p,sizeof(bytes),bytes);CryptReleaseContext(p,0);return ok?Hex(bytes,sizeof(bytes)):"";
}
std::string Secret() {
 char env[257]={0};DWORD n=GetEnvironmentVariableA("STOBE_ACTIVITY_TRANSPORT_SECRET",env,sizeof(env));
 if(n>=32 && n<sizeof(env))return std::string(env,n);
 // Provision alongside the DLL. Never put this secret into logs, prompts or source.
 HMODULE module=NULL;
 if(!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
   reinterpret_cast<LPCSTR>(&Secret),&module))return "";
 wchar_t path[32768]={0};DWORD count=GetModuleFileNameW(module,path,32768);if(!count || count>=32768)return "";
 std::wstring filename(path,count);size_t sep=filename.find_last_of(L"/\\");if(sep==std::wstring::npos)return "";
 filename=filename.substr(0,sep+1)+L"activity-transport.key";
 std::ifstream input(filename.c_str(),std::ios::binary);if(!input)return "";
 std::string value;char c;while(value.size()<257 && input.get(c))value+=c;
 while(!value.empty() && (value[value.size()-1]=='\r'||value[value.size()-1]=='\n'))value.erase(value.size()-1);
 return value.size()>=32 && value.size()<=256?value:std::string();
}
std::string Hmac(const std::string& key,const std::string& data) {
 HCRYPTPROV provider=0;HCRYPTKEY cryptoKey=0;HCRYPTHASH hash=0;std::string result;
 if(!CryptAcquireContext(&provider,NULL,NULL,PROV_RSA_AES,CRYPT_VERIFYCONTEXT))return result;
 std::vector<BYTE> blob(sizeof(BLOBHEADER)+sizeof(DWORD)+key.size());
 BLOBHEADER header={PLAINTEXTKEYBLOB,CUR_BLOB_VERSION,0,CALG_RC2};
 memcpy(&blob[0],&header,sizeof(header));DWORD keySize=static_cast<DWORD>(key.size());
 memcpy(&blob[sizeof(header)],&keySize,sizeof(keySize));memcpy(&blob[sizeof(header)+sizeof(keySize)],key.data(),key.size());
 if(CryptImportKey(provider,&blob[0],static_cast<DWORD>(blob.size()),0,CRYPT_IPSEC_HMAC_KEY,&cryptoKey) &&
    CryptCreateHash(provider,CALG_HMAC,cryptoKey,0,&hash)) {
  HMAC_INFO info={0};info.HashAlgid=CALG_SHA_256;BYTE bytes[32];DWORD size=sizeof(bytes);
  if(CryptSetHashParam(hash,HP_HMAC_INFO,reinterpret_cast<BYTE*>(&info),0) &&
     CryptHashData(hash,reinterpret_cast<const BYTE*>(data.data()),static_cast<DWORD>(data.size()),0) &&
     CryptGetHashParam(hash,HP_HASHVAL,bytes,&size,0) && size==32)result=Hex(bytes,size);
 }
 if(hash)CryptDestroyHash(hash);if(cryptoKey)CryptDestroyKey(cryptoKey);CryptReleaseContext(provider,0);return result;
}
bool EqualSignature(const std::string& a,const std::string& b) {
 if(a.size()!=64 || b.size()!=64)return false;unsigned difference=0;
 for(size_t i=0;i<64;++i)difference|=static_cast<unsigned char>(a[i]^b[i]);return difference==0;
}
bool UniqueFields(const Tree& t) {
 std::set<std::string> fields;
 for(Tree::const_iterator i=t.begin();i!=t.end();++i) {
  if(!i->first.empty() && !fields.insert(i->first).second)return false;
  if(!UniqueFields(i->second))return false;
 }return true;
}
bool Parse(const std::string& raw,Tree& t) {
 if(raw.size()>262144)return false;
 try {std::istringstream stream(raw);boost::property_tree::read_json(stream,t);return UniqueFields(t);}catch(...){return false;}
}
unsigned long long Number(const Tree& t,const char* field,unsigned long long max) {
 std::string s=t.get<std::string>(field,"");if(s.empty() || s.find_first_not_of("0123456789")!=std::string::npos)return 0;
 unsigned long long n=0;
 for(size_t i=0;i<s.size();++i){unsigned d=s[i]-'0';if(n>(max-d)/10)return 0;n=n*10+d;}return n;
}
bool SignedRequest(const std::string& body,unsigned long epoch,Tree& response) {
 if(body.size()>131072 || !PlaythroughSession::Allowed(epoch) || !Interaction::Allowed())return false;
 const std::string key=Secret(),nonce=Nonce();if(key.size()<32 || nonce.empty())return false;
 std::ostringstream time;time<<static_cast<unsigned long long>(std::time(NULL));
 const std::string signature=Hmac(key,"stobe.activity.v1\n"+time.str()+"\n"+nonce+"\n"+body);
 if(signature.empty())return false;
 const std::wstring url=ToWide(GetStobeServerHomeUrl()+"activity.php");
 URL_COMPONENTS parts={0};parts.dwStructSize=sizeof(parts);parts.dwHostNameLength=static_cast<DWORD>(-1);parts.dwUrlPathLength=static_cast<DWORD>(-1);
 if(!WinHttpCrackUrl(url.c_str(),static_cast<DWORD>(url.size()),0,&parts))return false;
 const std::wstring host(parts.lpszHostName,parts.dwHostNameLength),path(parts.lpszUrlPath,parts.dwUrlPathLength);
 HINTERNET session=WinHttpOpen(L"StobeActivity/1",WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,NULL,NULL,0);
 if(!session)return false;
 WinHttpSetTimeouts(session,5000,5000,5000,5000);
 HINTERNET connect=WinHttpConnect(session,host.c_str(),parts.nPort,0);
 HINTERNET request=connect?WinHttpOpenRequest(connect,L"POST",path.c_str(),NULL,WINHTTP_NO_REFERER,
   WINHTTP_DEFAULT_ACCEPT_TYPES,parts.nScheme==INTERNET_SCHEME_HTTPS?WINHTTP_FLAG_SECURE:0):NULL;
 bool ok=false;std::string raw,returnedSignature;
 if(request) {
  DWORD policy=WINHTTP_OPTION_REDIRECT_POLICY_NEVER;WinHttpSetOption(request,WINHTTP_OPTION_REDIRECT_POLICY,&policy,sizeof(policy));
  std::wstring headers=L"Content-Type: application/json\r\nX-Stobe-Activity-Time: "+ToWide(time.str())+
    L"\r\nX-Stobe-Activity-Nonce: "+ToWide(nonce)+L"\r\nX-Stobe-Activity-Signature: "+ToWide(signature)+L"\r\n";
  headers+=Interaction::Headers();headers+=PlaythroughSession::Headers(epoch);
  if(WinHttpSendRequest(request,headers.c_str(),static_cast<DWORD>(headers.size()),
      const_cast<char*>(body.data()),static_cast<DWORD>(body.size()),static_cast<DWORD>(body.size()),0) && WinHttpReceiveResponse(request,NULL)) {
   DWORD status=0,size=sizeof(status);wchar_t sig[128]={0};DWORD bytes=sizeof(sig);
   if(WinHttpQueryHeaders(request,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,NULL,&status,&size,NULL) && status==200 &&
      WinHttpQueryHeaders(request,WINHTTP_QUERY_CUSTOM,L"X-Stobe-Activity-Signature",sig,&bytes,NULL)) {
    returnedSignature.assign(sig,sig+wcslen(sig));
    char chunk[4096];DWORD count=0;ok=true;
    while(WinHttpReadData(request,chunk,sizeof(chunk),&count) && count) {
     raw.append(chunk,count);if(raw.size()>262144){ok=false;break;}
    }
   }
  }
  WinHttpCloseHandle(request);
 }
 if(connect)WinHttpCloseHandle(connect);WinHttpCloseHandle(session);
 return ok && PlaythroughSession::Allowed(epoch) && Interaction::Allowed() &&
  EqualSignature(returnedSignature,Hmac(key,"stobe.activity.response.v1\n"+nonce+"\n"+raw)) &&
  Parse(raw,response) && response.get<std::string>("ok","")=="true" && response.get<std::string>("requestNonce","")==nonce;
}
std::string Pair(unsigned actor,unsigned requester) {std::ostringstream s;s<<actor<<":"<<requester;return s.str();}
std::string Context(const Turn& t) { std::ostringstream s;s<<"{\"worldId\":\""<<t.world<<"\",\"actor\":"<<t.actor<<",\"requester\":"<<t.requester<<",\"now\":"<<t.now<<"}";return s.str(); }
bool FloatField(const Tree& t,const char* field,float& value) {
 std::string raw=t.get<std::string>(field,"");if(raw.empty()||raw.size()>32)return false;
 std::istringstream in(raw);in>>value;if(!in || !_finite(value))return false;
 char extra=0;return !(in>>extra);
}
bool ReadDiscoveryRef(const Tree& reference,Agreement& a) {
 if(reference.size()>2) return false;
 bool candidate=false,serial=false;
 for(Tree::const_iterator i=reference.begin();i!=reference.end();++i) {
  if(i->first=="candidateId" && !candidate && i->second.empty()) {
   a.discoveryCandidateId=i->second.get_value<std::string>(); candidate=true;
  } else if(i->first=="targetSerial" && !serial && i->second.empty()) {
   Tree wrapped; wrapped.put("n",i->second.get_value<std::string>());
   const unsigned long long value=Number(wrapped,"n",4294967295ULL);
   if(!value) return false;
   a.discoveryTargetSerial=static_cast<unsigned>(value); serial=true;
  } else return false;
 }
 return ValidDiscoveryReferenceShape(static_cast<unsigned>(reference.size()),candidate,serial) &&
        ValidDiscoveryReference(a.discoveryCandidateId,a.discoveryTargetSerial);
}
bool ReadAgreementV1(const Tree& t,const std::string& world,Stobe::ActivityV1Legacy::Agreement& a) {
 a.id=t.get<std::string>("id","");a.worldId=t.get<std::string>("worldId","");a.sourceId=t.get<std::string>("sourceId","");a.resourceId=t.get<std::string>("resourceId","");
 const std::string kind=t.get<std::string>("kind","");if(kind=="Hunt")a.kind=Stobe::ActivityV1Legacy::Hunt;else if(kind=="Mine")a.kind=Stobe::ActivityV1Legacy::Mine;else if(kind=="ClearGroup")a.kind=Stobe::ActivityV1Legacy::ClearGroup;else return false;
 a.actor=static_cast<unsigned>(Number(t,"actor",4294967295ULL));a.requester=static_cast<unsigned>(Number(t,"requester",4294967295ULL));
 a.quantity=static_cast<unsigned>(Number(t,"quantity",1000));a.maximumTargets=static_cast<unsigned>(Number(t,"maximumTargets",64));
 a.maximumReplans=static_cast<unsigned>(Number(t,"maximumReplans",16));a.expiresAt=Number(t,"expiresAt",0x7fffffffffffffffULL);a.noProgressTimeout=Number(t,"noProgressTimeout",86400);
 boost::optional<const Tree&> targets=t.get_child_optional("agreedTargets");
 if(targets)for(Tree::const_iterator i=targets->begin();i!=targets->end();++i){Tree wrap;wrap.put("n",i->second.get_value<std::string>());unsigned n=static_cast<unsigned>(Number(wrap,"n",4294967295ULL));if(!n || a.agreedTargets.size()>=64)return false;a.agreedTargets.push_back(n);}
 return a.worldId==world && HexId(world,32) && a.id.size()==41 && a.id.substr(0,9)=="activity-" && HexId(a.id.substr(9),32) &&
  a.actor && a.requester && a.actor!=a.requester && !a.sourceId.empty() && a.sourceId.size()<=256 &&
  a.resourceId.size()<=256 && a.maximumTargets && a.expiresAt && a.noProgressTimeout && (a.kind==Stobe::ActivityV1Legacy::ClearGroup || (a.quantity && !a.resourceId.empty()));
}
bool ReadAgreement(const Tree& t,const Tree& discovery,const Tree& route,const std::string& world,Agreement& a) {
 a.id=t.get<std::string>("id","");a.worldId=t.get<std::string>("worldId","");a.sourceId=t.get<std::string>("sourceId","");a.resourceId=t.get<std::string>("resourceId","");
 const std::string kind=t.get<std::string>("kind","");if(kind=="Hunt")a.kind=Hunt;else if(kind=="Mine")a.kind=Mine;else if(kind=="ClearGroup")a.kind=ClearGroup;else return false;
 a.actor=static_cast<unsigned>(Number(t,"actor",4294967295ULL));a.requester=static_cast<unsigned>(Number(t,"requester",4294967295ULL));
 if(!ReadDiscoveryRef(discovery,a)) return false;
 a.routeCandidateId=route.get<std::string>("candidateId","");a.routeWorldId=route.get<std::string>("worldId","");
 a.routeKind=route.get<std::string>("kind","");a.routeLabel=route.get<std::string>("label","");
 a.routeActor=static_cast<unsigned>(Number(route,"actorSerial",4294967295ULL));
 if(!FloatField(route,"x",a.routeX)||!FloatField(route,"y",a.routeY)||!FloatField(route,"z",a.routeZ))return false;
 a.quantity=static_cast<unsigned>(Number(t,"quantity",1000));a.maximumTargets=static_cast<unsigned>(Number(t,"maximumTargets",64));
 a.maximumReplans=static_cast<unsigned>(Number(t,"maximumReplans",16));a.expiresAt=Number(t,"expiresAt",0x7fffffffffffffffULL);a.noProgressTimeout=Number(t,"noProgressTimeout",86400);
 a.scopeVersion=HasField(t,"scopeVersion")?static_cast<unsigned>(Number(t,"scopeVersion",3)):1;
 boost::optional<const Tree&> campZone=t.get_child_optional("campZone");
 if(campZone) {
  if(a.scopeVersion!=3 || a.kind!=ClearGroup || campZone->size()!=2 ||
     !HasField(*campZone,"candidateId") || !HasField(*campZone,"scopeDigest")) return false;
  a.campQualified=true;
  a.campZoneCandidateId=campZone->get<std::string>("candidateId","");
  a.campZoneDigest=campZone->get<std::string>("scopeDigest","");
  if(a.campZoneCandidateId.size()<16 || a.campZoneCandidateId.size()>128 ||
     a.campZoneCandidateId.compare(0,3,"v1:")!=0 || !HexId(a.campZoneCandidateId.substr(3),48) ||
     !HexId(a.campZoneDigest,64)) return false;
 } else if(a.scopeVersion!=1) return false;
 boost::optional<const Tree&> targets=t.get_child_optional("agreedTargets");
 if(targets)for(Tree::const_iterator i=targets->begin();i!=targets->end();++i){Tree wrap;wrap.put("n",i->second.get_value<std::string>());unsigned n=static_cast<unsigned>(Number(wrap,"n",4294967295ULL));if(!n || a.agreedTargets.size()>=64)return false;a.agreedTargets.push_back(n);}
 return a.worldId==world && a.routeWorldId==a.worldId && a.routeActor==a.actor && HexId(world,32) && a.id.size()==41 && a.id.substr(0,9)=="activity-" && HexId(a.id.substr(9),32) &&
  a.routeCandidateId.size()>=1 && a.routeCandidateId.size()<=96 && a.routeLabel.size()>=1 && a.routeLabel.size()<=120 &&
  a.actor && a.requester && a.actor!=a.requester && !a.sourceId.empty() && a.sourceId.size()<=256 &&
  a.resourceId.size()<=256 && a.maximumTargets && a.expiresAt && a.noProgressTimeout && (a.kind==ClearGroup || (a.quantity && !a.resourceId.empty()));
}
bool Apply(const Tree& envelope,const std::string& world) {
 const std::string protocol=envelope.get<std::string>("protocol","");
 const std::string operation=envelope.get<std::string>("operation","");
 const unsigned revision=static_cast<unsigned>(Number(envelope,"revision",4294967295ULL));if(!revision)return false;
 const std::string scopeDigest=envelope.get<std::string>("scopeDigest","");
 std::string id;Agreement agreement;
 if(protocol=="stobe.activity.v1") {
  if(operation=="grant") {
   boost::optional<const Tree&> legacy=envelope.get_child_optional("agreement");
   Stobe::ActivityV1Legacy::Agreement old;
   if(!legacy || !ReadAgreementV1(*legacy,world,old))return false;
   id=old.id;
   {Lock lock;if(S().world!=world)return false;if(S().revisions[id]>=revision)return true;}
   if(!QueueActivityGrantV1Legacy(old,revision))return false;
   Lock lock;S().revisions[id]=revision;Tree receipt;receipt.put("id",id);receipt.put("worldId",world);
   receipt.put("revision",revision);receipt.put("actor",old.actor);receipt.put("requester",old.requester);
   receipt.put("scopeDigest",scopeDigest);receipt.put("protocol","stobe.activity.v1");receipt.put("serverTerminalRevoke","false");
   receipt.put("sourceId",old.sourceId);receipt.put("resourceId",old.resourceId);receipt.put("quantity",old.quantity);
   Tree targets;for(size_t i=0;i<old.agreedTargets.size();++i){Tree target;target.put_value(old.agreedTargets[i]);targets.push_back(std::make_pair("",target));}receipt.add_child("agreedTargets",targets);S().receipts[id]=receipt;return true;
  }
  if(operation=="cancel") {
   id=envelope.get<std::string>("agreementId","");
   if(envelope.get<std::string>("worldId","")!=world || id.empty() || !QueueActivityRevokeV1Legacy(id,world,revision))return false;
   Lock lock;S().revisions[id]=revision;Tree receipt;std::map<std::string,Tree>::iterator old=S().receipts.find(id);
   if(old!=S().receipts.end())receipt=old->second;
   receipt.put("id",id);receipt.put("worldId",world);receipt.put("revision",revision);
   receipt.put("actor",static_cast<unsigned>(Number(envelope,"actor",4294967295ULL)));
   receipt.put("requester",static_cast<unsigned>(Number(envelope,"requester",4294967295ULL)));
   receipt.put("scopeDigest",scopeDigest);receipt.put("protocol","stobe.activity.v1");receipt.put("serverTerminalRevoke","true");S().receipts[id]=receipt;return true;
  }
  return false;
 }
 if(protocol!="stobe.activity.v2" || !HexId(scopeDigest,64))return false;
 if(operation=="grant") {
  boost::optional<const Tree&> a=envelope.get_child_optional("agreement");boost::optional<const Tree&> discovery=envelope.get_child_optional("discoveryRef");boost::optional<const Tree&> route=envelope.get_child_optional("routeRef");
  if(!a || !discovery || !route || !ReadAgreement(*a,*discovery,*route,world,agreement))return false;
  agreement.scopeDigest=scopeDigest;
  agreement.handBack=envelope.get<std::string>("handback","")=="true";
  std::ostringstream canonicalEnvelope;boost::property_tree::write_json(canonicalEnvelope,envelope,false);
  agreement.dispatchEnvelope=canonicalEnvelope.str();
  if(agreement.dispatchEnvelope.empty())return false;
  id=agreement.id;
 } else if(operation=="cancel") {id=envelope.get<std::string>("agreementId","");if(envelope.get<std::string>("worldId","")!=world || id.empty())return false;}else return false;
 {Lock lock;if(S().world!=world)return false;if(S().revisions[id]>=revision)return true;}
 const bool queued=operation=="grant"?QueueActivityGrant(agreement,revision):QueueActivityRevoke(id,world,revision);
 if(queued){Lock lock;if(S().world==world){
  S().revisions[id]=revision;
  Tree receipt;
  if(operation=="cancel") {
   std::map<std::string,Tree>::iterator old=S().receipts.find(id);
   if(old==S().receipts.end())return false;
   receipt=old->second;
  } else {
   receipt.put("activityCandidateId",agreement.discoveryCandidateId);
   receipt.put("activityTargetSerial",agreement.discoveryTargetSerial);
   receipt.put("routeCandidateId",agreement.routeCandidateId);
   Tree targets;for(size_t i=0;i<agreement.agreedTargets.size();++i){Tree target;target.put_value(agreement.agreedTargets[i]);targets.push_back(std::make_pair("",target));}
   receipt.add_child("agreedTargets",targets);
   if(agreement.campQualified){Tree camp;camp.put("candidateId",agreement.campZoneCandidateId);camp.put("scopeDigest",agreement.campZoneDigest);receipt.add_child("campZone",camp);}
  }
  receipt.put("id",id);receipt.put("worldId",world);receipt.put("revision",revision);
  receipt.put("actor",operation=="grant"?agreement.actor:static_cast<unsigned>(Number(envelope,"actor",4294967295ULL)));
  receipt.put("requester",operation=="grant"?agreement.requester:static_cast<unsigned>(Number(envelope,"requester",4294967295ULL)));
  receipt.put("scopeDigest",scopeDigest);
  receipt.put("protocol","stobe.activity.v2");
  receipt.put("serverTerminalRevoke",operation=="cancel"?"true":"false");S().receipts[id]=receipt;
 }}return queued;
}
struct PollJob { Turn turn; std::vector<unsigned long long> acknowledged; std::string status; };
DWORD WINAPI PollWorker(LPVOID argument) {
 PollJob job=*static_cast<PollJob*>(argument);delete static_cast<PollJob*>(argument);
 const PlaythroughSession::Scope scope(job.turn.epoch);
 std::ostringstream body;body<<"{\"operation\":\"poll\",\"context\":"<<Context(job.turn)<<",\"acknowledged\":[";
 for(size_t i=0;i<job.acknowledged.size();++i){if(i)body<<",";body<<job.acknowledged[i];}body<<"]}";
 Tree response;std::vector<unsigned long long> ack;
 try {
  if(SignedRequest(body.str(),job.turn.epoch,response)) {
   boost::optional<Tree&> outbox=response.get_child_optional("result.outbox");
   if(outbox)for(Tree::const_iterator i=outbox->begin();i!=outbox->end();++i) {
    const unsigned long long sequence=Number(i->second,"sequence",0x7fffffffffffffffULL);
    boost::optional<const Tree&> envelope=i->second.get_child_optional("envelope");
    if(sequence && envelope && Apply(*envelope,job.turn.world))ack.push_back(sequence);
   }
  } else ack=job.acknowledged;
 } catch (...) {ack=job.acknowledged;}
 // In-progress observations first, so a hand-back event always precedes the terminal report.
 {
  std::vector<PendingEvent> batch;
  {Lock lock;if(S().world==job.turn.world)for(size_t n=0;n<8 && !S().events.empty();++n){batch.push_back(S().events.front());S().events.pop_front();}}
  for(size_t n=0;n<batch.size();++n) {
   PendingEvent& e=batch[n];
   Turn context=job.turn;context.actor=e.actor;context.requester=e.requester;context.now=e.now;
   const std::string body="{\"operation\":\"event\",\"context\":"+Context(context)+",\"agreementId\":\""+Escape(e.agreementId)+"\",\"event\":"+e.json+"}";
   Tree reply;bool sent=false;
   try{sent=SignedRequest(body,job.turn.epoch,reply);}catch(...){sent=false;}
   if(!sent){
    ++e.attempts;
    Lock lock;if(S().world==job.turn.world && e.attempts<3 && GetTickCount()-e.queuedTick<90000)S().events.push_front(e);
    break; // the transport is down or refusing: retry on a later poll, in order
   }
  }
 }
 // Report only controller-observed terminal state, never model claims.
 Tree statuses;
 if(Parse(job.status,statuses))for(Tree::const_iterator i=statuses.begin();i!=statuses.end();++i) {
  const Tree& state=i->second;const std::string id=state.get<std::string>("id","");
  const std::string phase=state.get<std::string>("phase","");
  if((phase!="complete" && phase!="cancelled" && phase!="failed") || state.get<std::string>("cleanupComplete","")!="true")continue;
  Tree receipt;unsigned revision=0;
  {Lock lock;if(S().world!=job.turn.world)break;
   std::map<std::string,Tree>::iterator r=S().receipts.find(id);if(r==S().receipts.end())continue;
   receipt=r->second;
   // Server-origin cancel/expiry is already durably terminal there. Native
   // cleanup still runs and blocks replacement independently; don't echo it
   // as a fresh autonomous terminal transition on every poll.
   if(receipt.get<std::string>("serverTerminalRevoke","")=="true")continue;
   revision=static_cast<unsigned>(Number(receipt,"revision",4294967295ULL));
   if(S().reported[id]>=revision)continue;
  }
  const std::string digest=receipt.get<std::string>("scopeDigest","");
  if(!HexId(digest,64) || state.get<std::string>("worldId","")!=job.turn.world ||
     Number(state,"revision",4294967295ULL)!=revision)continue;
  Turn context=job.turn;context.actor=static_cast<unsigned>(Number(receipt,"actor",4294967295ULL));context.requester=static_cast<unsigned>(Number(receipt,"requester",4294967295ULL));
  std::ostringstream report;report<<"{\"operation\":\"report\",\"context\":"<<Context(context)<<",\"agreementId\":\""<<Escape(id)
   <<"\",\"revision\":"<<revision<<",\"scopeDigest\":\""<<digest<<"\",\"status\":\""<<(phase=="complete"?"completed":phase)
   <<"\"";
  if(receipt.get<std::string>("protocol","")=="stobe.activity.v2") {
   report<<",\"executionScope\":{\"discoveryRef\":{\"candidateId\":\""<<Escape(receipt.get<std::string>("activityCandidateId",""))
   <<"\",\"targetSerial\":"<<Number(receipt,"activityTargetSerial",4294967295ULL)<<"},\"routeCandidateId\":\""
   <<Escape(receipt.get<std::string>("routeCandidateId",""))<<"\",\"agreedTargets\":[";
  boost::optional<Tree&> targetRows=receipt.get_child_optional("agreedTargets");bool comma=false;
  if(targetRows)for(Tree::iterator target=targetRows->begin();target!=targetRows->end();++target){if(comma)report<<",";comma=true;report<<target->second.get_value<std::string>();}
  report<<"]";boost::optional<Tree&> camp=receipt.get_child_optional("campZone");
  if(camp)report<<",\"campZone\":{\"candidateId\":\""<<Escape(camp->get<std::string>("candidateId",""))
   <<"\",\"scopeDigest\":\""<<Escape(camp->get<std::string>("scopeDigest",""))<<"\"}";
   report<<"}";
  }
  report<<"}";
  Tree response;
  if(SignedRequest(report.str(),job.turn.epoch,response)){Lock lock;if(S().world==job.turn.world)S().reported[id]=revision;}
 }
 {Lock lock;if(S().world==job.turn.world){S().acknowledgements.insert(S().acknowledgements.end(),ack.begin(),ack.end());S().polling=false;}}
 return 0;
}
}
std::string CaptureActivityChatTurn(unsigned actor,unsigned requester,const std::string& text) {
 if(!actor || !requester || actor==requester || text.empty() || text.size()>16384 || !Interaction::ManualInputAllowed())return "";
 Turn turn;turn.id=Nonce();turn.world=ActivityControllerWorldId();turn.now=ActivityControllerGameClock();turn.epoch=PlaythroughSession::Context();
 turn.actor=actor;turn.requester=requester;turn.text=text;
 const std::string captured=CaptureActivityChatFacts(actor,requester);
 if(captured.empty() || captured[0]!='{')return "";
 std::ostringstream facts;facts<<"{\"worldId\":\""<<turn.world<<"\",\"actor\":"<<actor<<",\"requester\":"<<requester;
 if(captured.size()>2)facts<<","<<captured.substr(1);else facts<<"}";
 turn.facts=facts.str();
 if(turn.id.empty() || !HexId(turn.world,32) || turn.facts.empty() || !PlaythroughSession::Allowed(turn.epoch))return "";
 Lock lock;
 if(S().world!=turn.world)return "";
 std::map<std::string,Offer>::iterator prior=S().displayed.find(Pair(actor,requester));
 if(prior!=S().displayed.end() && prior->second.world==turn.world) {
  const Tree& record=prior->second.record;std::ostringstream consent;
  consent<<"{\"origin\":\"native_player_chat\",\"worldId\":\""<<turn.world<<"\",\"actor\":"<<actor<<",\"requester\":"<<requester
   <<",\"proposalId\":\""<<Escape(record.get<std::string>("agreement.id",""))<<"\",\"revision\":"<<Number(record,"revision",4294967295ULL)
   <<",\"scopeDigest\":\""<<Escape(record.get<std::string>("scopeDigest",""))<<"\",\"proposalWasDisplayed\":true,\"playerText\":\""<<Escape(text)<<"\",\"quotedText\":\""<<Escape(text)<<"\"}";
  turn.consent=consent.str();
  if(record.get<std::string>("status","")=="proposed")S().displayed.erase(prior);
 }
 while(S().turns.size()>=64)S().turns.erase(S().turns.begin());S().turns[turn.id]=turn;return turn.id;
}
std::wstring PrepareActivityChatTurn(const std::string& id,const std::wstring& endpoint) {
 if(id.empty())return endpoint;Turn turn;
 {Lock lock;std::map<std::string,Turn>::iterator i=S().turns.find(id);if(i==S().turns.end())return endpoint;turn=i->second;}
 std::string body="{\"operation\":\"prepare_chat\",\"context\":"+Context(turn)+",\"playerText\":\""+Escape(turn.text)+"\",\"nativeFacts\":"+turn.facts;
 if(!turn.consent.empty())body+=",\"consent\":"+turn.consent;body+="}";
 Tree response;
 if(!SignedRequest(body,turn.epoch,response))return endpoint;
 const std::string ticket=response.get<std::string>("result.chatTicket","");if(!HexId(ticket,64))return endpoint;
 {Lock lock;if(S().world!=turn.world)return endpoint;std::map<std::string,Turn>::iterator i=S().turns.find(id);if(i==S().turns.end())return endpoint;i->second.ticket=ticket;}
 return endpoint+L"&activity_ticket="+ToWide(ticket);
}
std::string CanonicalSpeech(const std::string& text) {
 std::string result;bool whitespace=false;
 for(size_t i=0;i<text.size();++i) {
  const unsigned char c=static_cast<unsigned char>(text[i]);
  if(c==' '||c=='\r'||c=='\n'||c=='\t') { whitespace=!result.empty(); continue; }
  if(whitespace){result+=' ';whitespace=false;}result+=c;
 }return result;
}
void FinishActivityChatTurn(const std::string& id,bool displayed,const std::string& spokenText) {
 if(id.empty())return;Turn turn;
 {Lock lock;std::map<std::string,Turn>::iterator i=S().turns.find(id);if(i==S().turns.end())return;turn=i->second;S().turns.erase(i);}
 if(!displayed || turn.ticket.empty())return;
 Tree response;
 if(!SignedRequest("{\"operation\":\"chat_result\",\"context\":"+Context(turn)+",\"chatTicket\":\""+turn.ticket+"\"}",turn.epoch,response))return;
 boost::optional<Tree&> record=response.get_child_optional("result.record");if(!record)return;
 boost::optional<Tree&> terms=record->get_child_optional("agreement");boost::optional<Tree&> discovery=record->get_child_optional("discoveryRef");boost::optional<Tree&> route=record->get_child_optional("routeRef");Agreement agreement;
 if(!terms || !discovery || !route || !ReadAgreement(*terms,*discovery,*route,turn.world,agreement) || agreement.actor!=turn.actor || agreement.requester!=turn.requester ||
    !HexId(record->get<std::string>("scopeDigest",""),64))return;
 const std::string decision=response.get<std::string>("result.decision","");
 const std::string status=record->get<std::string>("status","");
 if(decision=="CANCEL" && status=="cancelled") {
  Lock lock;std::map<std::string,Offer>::iterator prior=S().displayed.find(Pair(turn.actor,turn.requester));
  if(prior!=S().displayed.end() && prior->second.record.get<std::string>("agreement.id","")==agreement.id)S().displayed.erase(prior);
  return;
 }
 bool bind=false;
 if(decision=="PROPOSE" && status=="proposed" && response.get<std::string>("result.offerDisplayed","")=="true") {
  const std::string offerText=response.get<std::string>("result.offerText","");
  bind=!offerText.empty() && CanonicalSpeech(offerText)==CanonicalSpeech(spokenText);
 } else if(decision=="ACCEPT" && status=="accepted") {
  // Keep the already displayed scope for explicit cancellation, not as a new offer.
  Tree consent;
  bind=Parse(turn.consent,consent) && consent.get<std::string>("proposalId","")==agreement.id &&
   consent.get<std::string>("scopeDigest","")==record->get<std::string>("scopeDigest","");
 }
 if(!bind)return;
 Offer offer;offer.record=*record;offer.world=turn.world;offer.actor=turn.actor;offer.requester=turn.requester;
 {Lock lock;if(S().world==turn.world)S().displayed[Pair(turn.actor,turn.requester)]=offer;}
}
void ResetActivityTransport() {Lock lock;S().world.clear();S().events.clear();S().turns.clear();S().displayed.clear();S().revisions.clear();S().receipts.clear();S().reported.clear();S().acknowledgements.clear();S().lastPoll=0;S().polling=false;}
void QueueActivityEvent(const std::string& agreementId,unsigned actor,unsigned requester,unsigned long gameNow,const std::string& eventJson) {
 if(agreementId.empty() || !actor || !requester || !gameNow || eventJson.empty() || eventJson.size()>1024 || eventJson[0]!='{')return;
 PendingEvent e;e.agreementId=agreementId;e.actor=actor;e.requester=requester;e.now=static_cast<Clock>(gameNow);e.json=eventJson;e.queuedTick=GetTickCount();
 Lock lock;if(S().world.empty())return;
 while(S().events.size()>=64)S().events.pop_front();
 S().events.push_back(e);
}
void UpdateActivityTransport() {
 const std::string status=ActivityControllerStatusJson();const std::string world=ActivityControllerWorldId();const Clock now=ActivityControllerGameClock();const unsigned long epoch=PlaythroughSession::Context();
 if(!HexId(world,32) || !PlaythroughSession::Allowed(epoch) || !Interaction::Allowed())return;
 PollJob* job=NULL;
 {Lock lock;
  if(S().world!=world){S().world=world;S().events.clear();S().turns.clear();S().displayed.clear();S().revisions.clear();S().receipts.clear();S().reported.clear();S().acknowledgements.clear();S().polling=false;S().lastPoll=0;}
  S().now=now;const DWORD tick=GetTickCount();if(S().polling || (S().lastPoll && tick-S().lastPoll<2000))return;
  S().lastPoll=tick;S().polling=true;job=new PollJob;job->status=status;job->turn.world=world;job->turn.now=now;job->turn.epoch=epoch;job->acknowledged.swap(S().acknowledgements);
 }
 HANDLE worker=PlaythroughSession::StartTask(NULL,0,PollWorker,job,0,NULL);
 if(worker)CloseHandle(worker);else{Lock lock;S().polling=false;S().acknowledgements.insert(S().acknowledgements.end(),job->acknowledged.begin(),job->acknowledged.end());delete job;}
}
} }
