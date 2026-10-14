#pragma once
#include "ActivityRuntime.h"
class RootObject;
class Character;
namespace Stobe { namespace Activity {
// Trusted typed transport only, game-thread only. Model output never grants authority.
class ConcreteRuntimeBindings : public RuntimeBindings {
public:
 ConcreteRuntimeBindings();
 void Bind(GameWorld*, const std::string&, Clock);
 std::string ProposalFacts(unsigned actor, unsigned requester);
 bool ImportGrant(const Agreement&, unsigned revision, std::string&);
 bool Revoke(const std::string&, unsigned revision);
 bool VerifyGrant(const Agreement&, Clock, std::string&);
 std::vector<NativeDestination> Discover(const Agreement&);
 bool Resolve(const Agreement&, unsigned, const std::string&, NativeDestination&, std::string&);
 bool ActivityPermitted(const Agreement&, const Request&, Target&, std::string&);
 Building* Resource(const Agreement&, unsigned);
 Inventory* Output(const Agreement&, Building*);
private:
 struct Grant { Agreement scope; unsigned revision; bool revoked; Character* actorIdentity; Character* requesterIdentity; std::map<unsigned,Character*> fixedIdentity; std::map<unsigned,std::string> fixedSource; Grant():revision(0),revoked(false),actorIdentity(NULL),requesterIdentity(NULL){} };
 struct Candidate { std::string agreement; NativeDestination point; RootObject* identity; Character* actorIdentity; Character* requesterIdentity; Clock observedAt; Candidate():identity(NULL),actorIdentity(NULL),requesterIdentity(NULL),observedAt(0){} };
 GameWorld* world_; std::string worldId_; Clock now_; unsigned sequence_;
 std::map<std::string,Grant> grants_;
 std::map<std::string,Candidate> candidates_;
 bool Refresh(const Agreement&, NativeDestination&, std::string&);
};
} }




