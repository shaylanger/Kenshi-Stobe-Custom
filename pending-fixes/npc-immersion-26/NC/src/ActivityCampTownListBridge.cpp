#include "ActivityCampTownListBridge.h"
#include "Globals.h"
#include "KenshiTownCompat.h"

#include <windows.h>
#include <wincrypt.h>
#include <objbase.h>
#include <stdint.h>
#include <kenshi/Globals.h>
#include <kenshi/SharedKing.h>
#include <sstream>

#pragma comment(lib,"advapi32.lib")

namespace Stobe { namespace ActivityCampNative {
namespace {
bool Usable(const void* p) { return p && reinterpret_cast<uintptr_t>(p)>0x1000; }

class SecureIds : public IOpaqueIdSource {
public:
  bool Next(const std::string& world,const std::string& session,
            unsigned long long sequence,std::string& out) {
    out.clear(); if(world.empty() || session.empty() || !sequence) return false;
    HCRYPTPROV provider=0; BYTE bytes[24];
    if(!CryptAcquireContext(&provider,NULL,NULL,PROV_RSA_AES,CRYPT_VERIFYCONTEXT)) return false;
    const BOOL ok=CryptGenRandom(provider,sizeof(bytes),bytes);
    CryptReleaseContext(provider,0);
    if(!ok) return false;
    static const char hex[]="0123456789abcdef";
    out="v1:";
    for(size_t i=0;i<sizeof(bytes);++i) { out+=hex[bytes[i]>>4]; out+=hex[bytes[i]&15]; }
    return true;
  }
};

class SecureDigest : public IConsentDigest {
public:
 bool Sha256Hex(const std::string& canonical,std::string& out) {
   out.clear(); if(canonical.size()>65536) return false;
   HCRYPTPROV provider=0; HCRYPTHASH hash=0; BYTE bytes[32]; DWORD size=sizeof(bytes);
   if(!CryptAcquireContext(&provider,NULL,NULL,PROV_RSA_AES,CRYPT_VERIFYCONTEXT)) return false;
   const bool ok=CryptCreateHash(provider,CALG_SHA_256,0,0,&hash) &&
     CryptHashData(hash,reinterpret_cast<const BYTE*>(canonical.data()),static_cast<DWORD>(canonical.size()),0) &&
     CryptGetHashParam(hash,HP_HASHVAL,bytes,&size,0) && size==sizeof(bytes);
   if(hash) CryptDestroyHash(hash);
   CryptReleaseContext(provider,0);
   if(!ok) return false;
   static const char hex[]="0123456789abcdef";
   for(size_t i=0;i<sizeof(bytes);++i) { out+=hex[bytes[i]>>4]; out+=hex[bytes[i]&15]; }
   return out.size()==64;
 }
};
}

// Private implementation type declared in the public catalog so standard
// library ownership stays out of the ABI-facing reader header.
class ActivityCampCatalog::SecureOpaqueIdSource : public IOpaqueIdSource {
public:
 bool Next(const std::string& world,const std::string& session,
           unsigned long long sequence,std::string& out) {
   return SecureIds().Next(world,session,sequence,out);
 }
};

bool CurrentGameTownListEnumerator::SnapshotTownListEntries(std::vector<RootObject*>& out) {
  out.clear();
  if(!g_mainThreadId || GetCurrentThreadId()!=g_mainThreadId || !Usable(shou) ||
     !Usable(shou->townList)) return false;
  try {
    lektor<RootObject*>& towns=shou->townList->getAllTowns();
    if(towns.count>4096) return false;
    out.reserve(towns.count);
    for(unsigned int i=0;i<towns.count;++i) {
      RootObject* entry=towns.stuff[i];
      if(Usable(entry)) out.push_back(entry);
    }
    return true;
  } catch(...) { out.clear(); return false; }
}

ActivityCampCatalog::ActivityCampCatalog()
  : source_(entries_), ids_(new SecureOpaqueIdSource()), registry_(new Registry(source_,*ids_)) {}

ActivityCampCatalog::~ActivityCampCatalog() {
  delete registry_;
  delete ids_;
}

void ActivityCampCatalog::BeginScope(const std::string& worldId,const std::string& sessionId) {
  if(!OnGameThread()) { Invalidate(); return; }
  registry_->BeginScope(worldId,sessionId);
}

void ActivityCampCatalog::Invalidate() {
  if(registry_) registry_->Invalidate();
}

bool ActivityCampCatalog::Discover(unsigned long long gameTime,std::vector<ZoneCandidate>& out) {
  out.clear();
  if(!OnGameThread() || !registry_) return false;
  return registry_->Discover(gameTime,out);
}

bool ActivityCampCatalog::Resolve(const std::string& candidateId,unsigned long long gameTime,
    unsigned long long maxAge,ZoneCandidate& out) {
  if(!OnGameThread() || !registry_) return false;
  return registry_->Resolve(candidateId,gameTime,maxAge,out);
}

bool ActivityCampCatalog::DigestConsent(const ZoneCandidate& zone,
    const std::vector<unsigned long long>& fixedTargets,std::string& digest) {
  digest.clear();
  if(!OnGameThread()) return false;
  SecureDigest provider;
  return BuildConsentDigest(zone,fixedTargets,provider,digest);
}

bool ActivityCampCatalog::IsWithinNativeBorders(const TownBaseFacts& anchor,
    float x,float y,float z,bool& inside) {
  inside=false;
  if(!OnGameThread()) return false;
  return source_.IsWithinNativeBorders(anchor,x,y,z,inside);
}

bool ActivityCampCatalog::OnGameThread() const {
  return g_mainThreadId && GetCurrentThreadId()==g_mainThreadId;
}
} }
