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
  receipt.planHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
  receipt.sessionGeneration = 7;

  Check("lowercase SHA-256 plan hash accepted", IsPlanHash(receipt.planHash));
  Check("missing plan hash rejected", !IsPlanHash(""));
  Check("short plan hash rejected", !IsPlanHash(receipt.planHash.substr(1)));
  Check("uppercase plan hash rejected", !IsPlanHash("0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"));
  Check("dispatch new request", ClassifyDuplicate(false, "", "wire-A", false, false) == DUPLICATE_NEW);
  Check("duplicate request is idempotently accepted", ClassifyDuplicate(true, "wire-A", "wire-A", true, false) == DUPLICATE_EXACT_ACCEPTED);
  Check("duplicate uncertain dispatch is not retried", ClassifyDuplicate(true, "wire-A", "wire-A", false, false) == DUPLICATE_EXACT_UNCERTAIN);
  Check("duplicate verified rejection remains not-started", ClassifyDuplicate(true, "wire-A", "wire-A", false, true) == DUPLICATE_EXACT_NOT_STARTED);
  Check("accepted dispatch takes precedence over stale rejection flag", ClassifyDuplicate(true, "wire-A", "wire-A", true, true) == DUPLICATE_EXACT_ACCEPTED);
  Check("same IDs with changed destination payload conflict", ClassifyDuplicate(true, "wire-A", "wire-B", true, false) == DUPLICATE_CONFLICT);
  Check("agreement/request composite key is unambiguous", RequestKey("a", "bc") != RequestKey("ab", "c"));

  Check("receipt matches exact identity and plan", MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 7, receipt.planHash));
  Check("wrong actor rejected", !MatchesCurrentScope(receipt, 42, 9, "agreement-A", "request-1", "load-epoch-7", 7, receipt.planHash));
  Check("wrong speaker rejected", !MatchesCurrentScope(receipt, 41, 10, "agreement-A", "request-1", "load-epoch-7", 7, receipt.planHash));
  Check("wrong agreement rejected", !MatchesCurrentScope(receipt, 41, 9, "agreement-B", "request-1", "load-epoch-7", 7, receipt.planHash));
  Check("wrong request rejected", !MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-2", "load-epoch-7", 7, receipt.planHash));
  Check("wrong world rejected", !MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-8", 7, receipt.planHash));
  Check("wrong plan hash rejected", !MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 7, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"));
  Check("missing plan hash rejected", !MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 7, ""));
  Check("missing native session generation rejected", !MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 0, receipt.planHash));
  Check("reload epoch invalidates old receipt", !MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-8", 8, receipt.planHash));
  Check("session reload invalidates old receipt", !MatchesCurrentScope(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 8, receipt.planHash));

  Check("route arrival requires endpoint", RouteArrival(false, 103, 200, 0, 0, 0, 0, 100, 200, 0));
  Check("follow arrival requires both at endpoint", RouteArrival(true, 100, 200, 0, 100, 206, 0, 100, 200, 0));
  Check("follower alone at endpoint is not follow completion", !RouteArrival(true, 100, 200, 0, 140, 206, 0, 100, 200, 0));
  Check("nearby but outside arrival radius is not completion", !RouteArrival(false, 109, 200, 0, 0, 0, 0, 100, 200, 0));

  Check("cleanup requires exact task, plan, and fresh absence", MatchesRelease(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 7, receipt.planHash, "order:41:12", true));
  Check("cleanup cannot claim success without fresh absence", !MatchesRelease(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 7, receipt.planHash, "order:41:12", false));
  Check("cleanup cannot release a different task", !MatchesRelease(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 7, receipt.planHash, "order:41:13", true));
  Check("cleanup rejects wrong request", !MatchesRelease(receipt, 41, 9, "agreement-A", "request-2", "load-epoch-7", 7, receipt.planHash, "order:41:12", true));
  Check("cleanup rejects wrong plan hash", !MatchesRelease(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 7, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", "order:41:12", true));
  Check("cleanup rejects wrong actor", !MatchesRelease(receipt, 42, 9, "agreement-A", "request-1", "load-epoch-7", 7, receipt.planHash, "order:41:12", true));
  Check("cleanup rejects wrong speaker", !MatchesRelease(receipt, 41, 10, "agreement-A", "request-1", "load-epoch-7", 7, receipt.planHash, "order:41:12", true));
  Check("cleanup rejects wrong agreement", !MatchesRelease(receipt, 41, 9, "agreement-B", "request-1", "load-epoch-7", 7, receipt.planHash, "order:41:12", true));
  Check("cleanup rejects missing session generation", !MatchesRelease(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 0, receipt.planHash, "order:41:12", true));
  Check("cleanup cannot cross reload epoch", !MatchesRelease(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-8", 8, receipt.planHash, "order:41:12", true));
  Check("cleanup cannot cross session generation", !MatchesRelease(receipt, 41, 9, "agreement-A", "request-1", "load-epoch-7", 8, receipt.planHash, "order:41:12", true));

  // NC17: player-faction companion as an activity partner (player is the requester).
  // args: dead, unconscious, actorIsPlayerChar, actorInPlayerFaction, requesterIsPlayer, actorIsRequester, hasOrders, hasPlayerOrders, listEmpty
  Check("NC17 ordinary NPC idle is allowed", ClassifyStartActor(false, false, false, false, true, false, true, false, true) == START_ACTOR_OK);
  Check("NC17 squad companion idle with player requester is allowed", ClassifyStartActor(false, false, false, true, true, false, true, false, true) == START_ACTOR_OK);
  Check("NC17 squad companion flagged player character with player requester is allowed", ClassifyStartActor(false, false, true, true, true, false, true, false, true) == START_ACTOR_OK);
  Check("NC17 squad companion without player requester is refused", ClassifyStartActor(false, false, false, true, false, false, true, false, true) == START_ACTOR_PLAYER_FACTION_NO_PLAYER_REQUESTER);
  Check("NC17 non-squad player character actor is still refused", ClassifyStartActor(false, false, true, false, true, false, true, false, true) == START_ACTOR_PLAYER_CHARACTER);
  Check("NC17 actor equal to requester is refused", ClassifyStartActor(false, false, true, true, true, true, true, false, true) == START_ACTOR_IS_REQUESTER);
  Check("NC17 dead squad companion is refused", ClassifyStartActor(true, false, false, true, true, false, true, false, true) == START_ACTOR_DOWN);
  Check("NC17 unconscious squad companion is refused", ClassifyStartActor(false, true, false, true, true, false, true, false, true) == START_ACTOR_DOWN);
  Check("NC17 squad companion with player orders is refused", ClassifyStartActor(false, false, false, true, true, false, true, true, true) == START_ACTOR_HAS_PLAYER_ORDERS);
  Check("NC17 squad companion with an order list is refused", ClassifyStartActor(false, false, false, true, true, false, true, false, false) == START_ACTOR_HAS_ORDERS);
  Check("NC17 missing orders receiver is refused", ClassifyStartActor(false, false, false, true, true, false, false, false, true) == START_ACTOR_NO_ORDERS_RECEIVER);
  Check("NC17 non-squad NPC with player orders is refused", ClassifyStartActor(false, false, false, false, true, false, true, true, true) == START_ACTOR_HAS_PLAYER_ORDERS);
  Check("NC17 non-squad NPC with an order list is refused", ClassifyStartActor(false, false, false, false, true, false, true, false, false) == START_ACTOR_HAS_ORDERS);
  Check("NC17 suffixes are distinct and stable", std::string(StartActorSuffix(START_ACTOR_HAS_PLAYER_ORDERS)) == "has_player_orders" &&
        std::string(StartActorSuffix(START_ACTOR_PLAYER_CHARACTER)) == "player_character" && std::string(StartActorSuffix(START_ACTOR_OK)) == "ok");

  return failures ? 1 : 0;
}
