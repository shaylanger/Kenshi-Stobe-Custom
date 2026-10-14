#pragma once
#include "ActivityNativeExecutor.h"
#include <map>
namespace Stobe { namespace Activity {
// Adapter to the authoritative server agreement store and registered discovery
// points. These are game-thread calls; no model output may implement authority.
class RuntimeBindings {
public:
 virtual ~RuntimeBindings() {}
 virtual bool VerifyGrant(const Agreement&, Clock, std::string&) = 0;
 virtual std::vector<NativeDestination> Discover(const Agreement&) = 0;
 virtual bool Resolve(const Agreement&, unsigned int target, const std::string& candidate,
                      NativeDestination&, std::string&) = 0;
 virtual bool ActivityPermitted(const Agreement&, const Request&, Target&, std::string&) = 0;
 virtual Building* Resource(const Agreement&, unsigned int) = 0;
 virtual Inventory* Output(const Agreement&, Building*) = 0;
};
class NativeHost : public Host, private NativePolicy {
public:
 explicit NativeHost(RuntimeBindings&);
 void Bind(GameWorld*, const std::string&, Clock);
 bool Authorized(const Agreement&, Clock, std::string&);
 Facts Observe(const Agreement&, unsigned int);
 std::vector<Target> Candidates(const Agreement&);
 bool Dispatch(const Agreement&, const Request&, std::string&);
 Receipt Poll(const std::string&);
 bool CancelOwned(const std::string&);
private:
 RuntimeBindings& bindings_; NativeExecutor executor_;
 GameWorld* world_; std::string worldId_; Clock now_;
 Facts frameFacts_; bool frameObserved_;
 std::map<unsigned int, NativeDestination> targets_;
 bool Revalidate(const Agreement&, const Request&, Target&, std::string&);
 Building* ResolveResource(const Agreement&, unsigned int);
 Inventory* ResourceOutput(const Agreement&, Building*);
};
// Explicit integration owner. One finite activity per actor. A cancelled goal
// whose native cleanup is unconfirmed remains retained and prevents replacement.
// No thread, timer, network endpoint or game hook is started by this class.
class Runtime {
public:
 explicit Runtime(RuntimeBindings&);
 ~Runtime();
 bool Start(const Agreement&, GameWorld*, const std::string&, Clock, std::string&);
 void Tick(GameWorld*, const std::string&, Clock);
 bool Cancel(const std::string& agreementId, const std::string& reason);
 bool Reset(GameWorld*, const std::string&, Clock, std::string&);
 bool Status(const std::string&, Phase&, std::string&) const;
 bool CleanupComplete(const std::string&) const;
private:
 Runtime(const Runtime&); Runtime& operator=(const Runtime&);
 struct Entry { NativeHost host; Goal goal; explicit Entry(RuntimeBindings& b):host(b){} };
 RuntimeBindings& bindings_; std::map<std::string,Entry*> entries_;
};
} }