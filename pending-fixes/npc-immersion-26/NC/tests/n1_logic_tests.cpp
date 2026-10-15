// Offline tests for the N1 pure logic headers. Build: g++ -std=c++11 -I../src n1_logic_tests.cpp -o n1_logic_tests
#include "ActivityEventTracker.h"
#include "ActivityHandBackPolicy.h"
#include "FollowExpiryPolicy.h"
#include "NativeAiOrdersJson.h"
#include <cstdio>
#include <cstdlib>
using namespace Stobe;
static int failures = 0, checks = 0;
#define CHECK(c) do { ++checks; if (!(c)) { ++failures; std::printf("FAIL line %d: %s\n", __LINE__, #c); } } while (0)

static Activity::Events::Observation Obs(const char* phase, unsigned long ms) {
 Activity::Events::Observation o; o.agreementId = "activity-aa"; o.phase = phase; o.nowMs = ms; o.resource = "Meat"; o.quantity = 5;
 return o;
}
static void TestEvents() {
 using namespace Activity::Events;
 Tracker t; std::vector<Event> ev;
 // baseline: no events on first observation, even with deliveries already present
 Observation o = Obs("routing", 1000); o.delivered = 2; t.Observe(o, ev); CHECK(ev.empty());
 // route pending then finished -> exactly one arrival with place
 o = Obs("travelling", 2000); o.routePending = true; o.delivered = 2; o.routeLabel = "Squin \"Town\""; t.Observe(o, ev); CHECK(ev.empty());
 o = Obs("searching", 3000); o.delivered = 2; o.routeLabel = "Squin \"Town\""; t.Observe(o, ev);
 CHECK(ev.size() == 1 && ev[0].kind == "arrival" && ev[0].id == "arr");
 CHECK(ev[0].json == "{\"id\":\"arr\",\"kind\":\"arrival\",\"place\":\"Squin Town\"}");
 ev.clear(); o.nowMs = 3500; t.Observe(o, ev); CHECK(ev.empty()); // no repeat
 // progress only on increase, id unique
 o = Obs("performing", 4000); o.delivered = 3; t.Observe(o, ev);
 CHECK(ev.size() == 1 && ev[0].id == "p3" && ev[0].json.find("\"delivered\":3") != std::string::npos);
 CHECK(ev[0].json.find("\"quantity\":5") != std::string::npos && ev[0].json.find("\"resource\":\"Meat\"") != std::string::npos);
 ev.clear(); o.nowMs = 4500; t.Observe(o, ev); CHECK(ev.empty());
 o.delivered = 2; o.nowMs = 4600; t.Observe(o, ev); CHECK(ev.empty()); // decrease: nothing
 // threat: first fires, same serial never again, second serial blocked by cooldown, then allowed
 o = Obs("performing", 10000); o.delivered = 3; o.threatObserved = true; o.threatSerial = 77; o.threatName = "Bone Dog"; o.threatDistance = 250;
 t.Observe(o, ev);
 CHECK(ev.size() == 1 && ev[0].kind == "threat" && ev[0].id == "t1" && ev[0].json.find("\"distance\":250") != std::string::npos);
 ev.clear(); o.nowMs = 12000; t.Observe(o, ev); CHECK(ev.empty());
 o.threatSerial = 78; o.nowMs = 15000; t.Observe(o, ev); CHECK(ev.empty()); // cooldown 30 s
 o.nowMs = 41000; t.Observe(o, ev); CHECK(ev.size() == 1 && ev[0].id == "t2");
 // distance out of range is omitted, name optional
 ev.clear(); t = Tracker(); o = Obs("performing", 1); t.Observe(o, ev);
 o.threatObserved = true; o.threatSerial = 5; o.threatDistance = 99999; o.nowMs = 2; t.Observe(o, ev);
 CHECK(ev.size() == 1 && ev[0].json == "{\"id\":\"t1\",\"kind\":\"threat\"}");
 // injury: drop >= 15 reports once; small drops accumulate to baseline; cooldown; heal resets baseline
 ev.clear(); t = Tracker();
 o = Obs("performing", 1000); o.actorHealthValid = true; o.actorPercent = 100; o.requesterHealthValid = true; o.requesterPercent = 100; t.Observe(o, ev);
 o.actorPercent = 90; o.nowMs = 2000; t.Observe(o, ev); CHECK(ev.empty());
 o.actorPercent = 80; o.nowMs = 3000; t.Observe(o, ev);
 CHECK(ev.size() == 1 && ev[0].id == "ia1" && ev[0].json.find("\"who\":\"actor\"") != std::string::npos && ev[0].json.find("\"healthPercent\":80") != std::string::npos);
 ev.clear(); o.actorPercent = 55; o.nowMs = 8000; t.Observe(o, ev); CHECK(ev.empty()); // cooldown 20 s
 o.nowMs = 24000; t.Observe(o, ev); CHECK(ev.size() == 1 && ev[0].id == "ia2");
 ev.clear(); o.requesterPercent = 60; o.nowMs = 25000; t.Observe(o, ev);
 CHECK(ev.size() == 1 && ev[0].id == "ir1" && ev[0].json.find("\"who\":\"requester\"") != std::string::npos);
 ev.clear(); o.actorPercent = 100; o.nowMs = 26000; t.Observe(o, ev); CHECK(ev.empty()); // heal: baseline back up
 o.actorPercent = 70; o.nowMs = 60000; t.Observe(o, ev); CHECK(ev.size() == 1 && ev[0].id == "ia3");
 // invalid health never fires
 ev.clear(); t = Tracker(); o = Obs("performing", 1); t.Observe(o, ev); o.actorHealthValid = false; o.actorPercent = 0; o.nowMs = 2; t.Observe(o, ev); CHECK(ev.empty());
 // dead phases emit nothing
 ev.clear(); t = Tracker(); o = Obs("performing", 1); t.Observe(o, ev);
 o = Obs("failed", 2); o.delivered = 4; o.threatObserved = true; o.threatSerial = 9; t.Observe(o, ev); CHECK(ev.empty());
 o = Obs("cleanup_pending", 3); o.delivered = 4; t.Observe(o, ev); CHECK(ev.empty());
 // hand-back: returning and handback once each
 ev.clear(); t = Tracker(); o = Obs("complete", 1); t.Observe(o, ev);
 o.handBackReturning = true; o.nowMs = 2; t.Observe(o, ev); CHECK(ev.size() == 1 && ev[0].json == "{\"id\":\"ret\",\"kind\":\"phase\",\"phase\":\"returning\"}");
 ev.clear(); o.nowMs = 3; t.Observe(o, ev); CHECK(ev.empty());
 o.handBackCount = 4; o.nowMs = 4; t.Observe(o, ev);
 CHECK(ev.size() == 1 && ev[0].json == "{\"id\":\"hb\",\"kind\":\"handback\",\"count\":4,\"toRequester\":true,\"resource\":\"Meat\"}");
 ev.clear(); o.nowMs = 5; t.Observe(o, ev); CHECK(ev.empty());
 // per-agreement isolation and Forget
 ev.clear(); t = Tracker(); o = Obs("performing", 1); t.Observe(o, ev);
 Observation o2 = o; o2.agreementId = "activity-bb"; t.Observe(o2, ev);
 o.delivered = 1; o.nowMs = 2; t.Observe(o, ev); o2.delivered = 1; o2.nowMs = 2; t.Observe(o2, ev);
 CHECK(ev.size() == 2 && ev[0].id == "p1" && ev[1].id == "p1" && ev[0].agreementId != ev[1].agreementId);
 // id charset and length
 for (size_t i = 0; i < ev.size(); ++i) { CHECK(ev[i].id.size() >= 1 && ev[i].id.size() <= 64); CHECK(ev[i].id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:_-") == std::string::npos); }
 // total cap
 ev.clear(); t = Tracker(); o = Obs("performing", 1); t.Observe(o, ev);
 for (unsigned i = 1; i <= 100; ++i) { o.delivered = i; o.nowMs = 1 + i; t.Observe(o, ev); }
 CHECK(ev.size() == Tracker::MaxEvents());
 // SafeText: quotes/backslash/control removed, cut on UTF-8 boundary
 CHECK(SafeText("a\"b\\c\nd", 48) == "abcd");
 CHECK(SafeText("ab\xC3\xA9" "cd", 3) == "ab"); // would cut inside the 2-byte e-acute
}
static Activity::HandBack::Input Ready() {
 Activity::HandBack::Input i; i.enabled = true; i.delivers = true; i.goalComplete = true; i.goalEnded = true; i.cleanupComplete = true;
 i.delivered = 3; i.inActorInventory = 5; i.nowMs = 1000; return i;
}
static void TestHandBack() {
 using namespace Activity::HandBack;
 { Machine m; Input i = Ready(); i.goalEnded = false; i.goalComplete = false; CHECK(m.Step(i).action == ActNone && !m.Finished() && !m.HoldsTerminal()); }
 { Machine m; Input i = Ready(); i.enabled = false; m.Step(i); CHECK(m.Finished() && m.Status() == "not_applicable" && m.Reason() == "handback_not_requested"); }
 { Machine m; Input i = Ready(); i.delivers = false; m.Step(i); CHECK(m.Finished() && m.Status() == "not_applicable"); }
 { Machine m; Input i = Ready(); i.delivered = 0; m.Step(i); CHECK(m.Finished() && m.Status() == "not_applicable"); }
 { Machine m; Input i = Ready(); i.goalComplete = false; m.Step(i); CHECK(m.Finished() && m.Status() == "kept_by_npc" && m.Reason() == "activity_not_completed"); }
 { Machine m; Input i = Ready(); i.inActorInventory = 0; m.Step(i); CHECK(m.Finished() && m.Status() == "kept_by_npc"); }
 { Machine m; Input i = Ready(); i.cleanupComplete = false; CHECK(m.Step(i).action == ActNone && !m.HoldsTerminal()); }
 { // far: start follow once, walk, then near -> transfer exactly min(delivered, stock), success -> release -> finished
  Machine m; Input i = Ready(); i.distance = 200; i.inActorInventory = 2;
  Output o = m.Step(i); CHECK(o.action == ActStartFollow && m.HoldsTerminal());
  m.FollowStartResult(true, "", i); i.followStarted = true; i.nowMs += 500;
  o = m.Step(i); CHECK(o.action == ActNone && m.Returning());
  i.distance = 8; i.nowMs += 500; o = m.Step(i); CHECK(o.action == ActTransfer && o.amount == 2);
  m.TransferResult(true, 2, "", i); CHECK(m.Status() == "delivered" && m.Amount() == 2 && !m.Finished() && m.CurrentStage() == Releasing);
  i.nowMs += 500; o = m.Step(i); CHECK(o.action == ActReleaseFollow);
  i.followReleased = true; i.nowMs += 500; o = m.Step(i); CHECK(m.Finished() && o.action == ActNone && m.Status() == "delivered");
 }
 { // already near: transfer straight away without a follow; finishing needs no release
  Machine m; Input i = Ready(); i.distance = 3; Output o = m.Step(i); CHECK(o.action == ActTransfer && o.amount == 3);
  m.TransferResult(true, 3, "", i); CHECK(m.Finished() && m.Status() == "delivered");
 }
 { // transfer failures: 3 attempts spaced by the retry delay, then kept_by_npc
  Machine m; Input i = Ready(); i.distance = 3; Output o = m.Step(i); CHECK(o.action == ActTransfer);
  m.TransferResult(false, 0, "recipient_full", i); CHECK(!m.Finished());
  i.nowMs += 500; CHECK(m.Step(i).action == ActNone);
  i.nowMs += 2000; CHECK(m.Step(i).action == ActTransfer); m.TransferResult(false, 0, "recipient_full", i);
  i.nowMs += 2500; CHECK(m.Step(i).action == ActTransfer); m.TransferResult(false, 0, "recipient_full", i);
  CHECK(m.Finished() && m.Status() == "kept_by_npc" && m.Reason() == "transfer_failed:recipient_full" && m.Amount() == 0);
 }
 { // follow rejected -> kept_by_npc, nothing to release
  Machine m; Input i = Ready(); i.distance = 100; CHECK(m.Step(i).action == ActStartFollow);
  m.FollowStartResult(false, "existing_travel_controller", i); i.nowMs += 10; m.Step(i);
  CHECK(m.Finished() && m.Status() == "kept_by_npc" && m.Reason() == "follow_rejected:existing_travel_controller");
 }
 { // follow fails while walking
  Machine m; Input i = Ready(); i.distance = 100; m.Step(i); m.FollowStartResult(true, "", i); i.followStarted = true;
  i.followFailed = true; i.nowMs += 100; m.Step(i); CHECK(m.Status() == "kept_by_npc" && m.Reason() == "follow_failed" && m.CurrentStage() == Releasing);
 }
 { // timeout while walking
  Machine m; Input i = Ready(); i.distance = 100; m.Step(i); m.FollowStartResult(true, "", i); i.followStarted = true;
  i.nowMs += Machine::TimeoutMs() + 1; m.Step(i); CHECK(m.Status() == "kept_by_npc" && m.Reason() == "handback_timeout");
  i.nowMs += Machine::ReleaseTimeoutMs() + 1; m.Step(i); CHECK(m.Finished());
 }
 { // requester vanished
  Machine m; Input i = Ready(); i.distance = 100; m.Step(i); i.requesterAvailable = false; i.nowMs += 50; m.Step(i);
  CHECK(m.Status() == "kept_by_npc" && m.Reason() == "actor_or_requester_unavailable");
 }
 { // Finished stays finished and quiet
  Machine m; Input i = Ready(); i.enabled = false; m.Step(i); i.enabled = true; CHECK(m.Step(i).action == ActNone && m.Status() == "not_applicable");
 }
}
static void TestFollowExpiry() {
 using namespace FollowExpiry;
 CHECK(ShouldExpire(1000, 1000 + 86400, kDefaultLimitGameSeconds, false, false));
 CHECK(!ShouldExpire(1000, 1000 + 86399, kDefaultLimitGameSeconds, false, false));
 CHECK(!ShouldExpire(1000, 1000 + 999999, kDefaultLimitGameSeconds, true, false));  // squad member
 CHECK(!ShouldExpire(1000, 1000 + 999999, kDefaultLimitGameSeconds, false, true));  // owned travel
 CHECK(!ShouldExpire(1000, 1000 + 999999, 0, false, false));                        // disabled
 CHECK(!ShouldExpire(0, 999999, kDefaultLimitGameSeconds, false, false));           // unknown start
 CHECK(AgeSeconds(500, 400) == 0 && AgeSeconds(500, 800) == 300 && AgeSeconds(0, 800) == 0);
 Info none; CHECK(TemporaryCompanionJson(none, false, false, "") == "{\"observed\":true,\"present\":false}");
 Info i; i.present = true; i.startGameTs = 1000; i.nowGameTs = 4600;
 CHECK(TemporaryCompanionJson(i, false, false, "") == "{\"observed\":true,\"present\":true,\"source\":\"legacy_follow\",\"squad_member\":false,\"since_game_ts\":1000,\"age_game_seconds\":3600,\"expires_gamets\":87400}");
 CHECK(TemporaryCompanionJson(i, true, false, "").find("expires_gamets") == std::string::npos);
 CHECK(TemporaryCompanionJson(i, false, true, "activity-ab\"c").find("\"source\":\"owned_travel\"") != std::string::npos);
 CHECK(TemporaryCompanionJson(i, false, true, "activity-ab\"c").find("\"agreement_id\":\"activity-abc\"") != std::string::npos);
 Info unknown; unknown.present = true; CHECK(TemporaryCompanionJson(unknown, false, false, "").find("since_game_ts") == std::string::npos);
}
static void TestOrdersJson() {
 using namespace NativeAiOrdersJson;
 std::vector<OrderRow> rows; CHECK(PlayerOrdersJson(false, rows) == "null"); CHECK(PlayerOrdersJson(true, rows) == "[]");
 OrderRow a; a.type = "Follow"; a.target.serial = 12; a.target.name = "Shay \"X\""; rows.push_back(a);
 OrderRow b; b.type = "Move"; rows.push_back(b); // not a server-known type: dropped
 OrderRow c; c.type = "Hold"; rows.push_back(c);
 CHECK(PlayerOrdersJson(true, rows) == "[{\"type\":\"Follow\",\"target\":{\"serial\":12,\"name\":\"Shay \\\"X\\\"\"}},{\"type\":\"Hold\",\"target\":null}]");
 CHECK(ActiveJobJson(false, "") == "{\"observed\":false}");
 CHECK(ActiveJobJson(true, "") == "{\"observed\":true,\"name\":null}");
 CHECK(ActiveJobJson(true, "Mining") == "{\"observed\":true,\"name\":\"Mining\"}");
}
int main() {
 TestEvents(); TestHandBack(); TestFollowExpiry(); TestOrdersJson();
 std::printf("RESULT N1_LOGIC_TESTS %s checks=%d failures=%d\n", failures ? "FAIL" : "PASS", checks, failures);
 return failures ? 1 : 0;
}
