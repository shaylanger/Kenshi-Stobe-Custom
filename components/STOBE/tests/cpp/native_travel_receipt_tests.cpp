#include "NativeTravelReceiptPolicy.h"
#include <iostream>
#include <string>

namespace {
int failures = 0;
void Check(const char *name, bool value) {
  if (value) std::cout << "PASS " << name << "\n";
  else { std::cerr << "FAIL " << name << "\n"; ++failures; }
}
}

int main() {
  using namespace Stobe::NativeTravelReceiptPolicy;
  Scope receipt;
  receipt.actor = 41; receipt.speaker = 9;
  receipt.agreement = "agreement-A"; receipt.request = "request-1";
  receipt.world = "load-epoch-7"; receipt.task = "order:41:12";

  Check("dispatch new request", ClassifyDuplicate(false, "", "wire-A", false) == DUPLICATE_NEW);
  Check("duplicate request is idempotently accepted", ClassifyDuplicate(true, "wire-A", "wire-A", true) == DUPLICATE_EXACT_ACCEPTED);
  Check("duplicate uncertain dispatch is not retried", ClassifyDuplicate(true, "wire-A", "wire-A", false) == DUPLICATE_EXACT_UNCERTAIN);
  Check("same IDs with changed destination payload conflict", ClassifyDuplicate(true, "wire-A", "wire-B", true) == DUPLICATE_CONFLICT);
  Check("agreement/request composite key is unambiguous", RequestKey("a", "bc") != RequestKey("ab", "c"));

  Check("receipt matches exact actor and world", MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7"));
  Check("wrong actor rejected", !MatchesCurrentScope(receipt, 42, 9, "agreement-A", "request-1", "load-epoch-7"));
  Check("wrong speaker rejected", !MatchesCurrentScope(receipt, 41, 10, "agreement-A", "request-1", "load-epoch-7"));
  Check("wrong agreement/request rejected", !MatchesCurrentScope(receipt, 41, 9, "agreement-B", "request-1", "load-epoch-7"));
  Check("reload epoch invalidates old receipt", !MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-8"));

  Check("route arrival requires endpoint", RouteArrival(false, 103, 200, 0, 0, 0, 0, 100, 200, 0));
  Check("follow arrival requires both at endpoint", RouteArrival(true, 100, 200, 0, 100, 206, 0, 100, 200, 0));
  Check("follower alone at endpoint is not follow completion", !RouteArrival(true, 100, 200, 0, 140, 206, 0, 100, 200, 0));
  Check("nearby but outside arrival radius is not completion", !RouteArrival(false, 109, 200, 0, 0, 0, 0, 100, 200, 0));

  Check("cleanup requires exact task and fresh absence", MatchesRelease(receipt, 41, 9, "agreement-A", "load-epoch-7", "order:41:12", true));
  Check("cleanup cannot claim success without fresh absence", !MatchesRelease(receipt, 41, 9, "agreement-A", "load-epoch-7", "order:41:12", false));
  Check("cleanup cannot release a different task", !MatchesRelease(receipt, 41, 9, "agreement-A", "load-epoch-7", "order:41:13", true));
  Check("cleanup cannot cross reload epoch", !MatchesRelease(receipt, 41, 9, "agreement-A", "load-epoch-8", "order:41:12", true));

  return failures ? 1 : 0;
}
