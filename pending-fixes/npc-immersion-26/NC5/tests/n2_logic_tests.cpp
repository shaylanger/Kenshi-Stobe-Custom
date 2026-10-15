// N2 pure-logic tests. Build: bash run.sh (g++ -std=c++11 -I../src)
#include "N2Policy.h"
#include <iostream>
using namespace Stobe::N2Policy;
static int g_fail = 0, g_pass = 0;
#define CHECK(c) do { if (c) ++g_pass; else { ++g_fail; std::cout << "FAIL line " << __LINE__ << ": " #c "\n"; } } while (0)
static bool Has(const std::string &s, const char *x) { return s.find(x) != std::string::npos; }

static void TestAttention() {
  AttentionInputs a;
  a.bloodPct = 140; a.busy = true; a.busyReason = std::string("repairing \"the\" wall\nnow ") + std::string(80, 'x');
  std::string j = AttentionJson(a);
  CHECK(Has(j, "\"observed\":true"));
  CHECK(Has(j, "\"blood_pct\":100"));
  CHECK(Has(j, "\"busy\":true"));
  CHECK(Has(j, "\\\"the\\\""));
  CHECK(!Has(j, "\n"));
  CHECK(Has(j, "\"busy_reason\":\""));
  CHECK(AsciiTruncate(a.busyReason, 40).size() == 40);
  a.bloodPct = 0; CHECK(Has(AttentionJson(a), "\"blood_pct\":0"));
  a.bloodPct = -1; CHECK(Has(AttentionJson(a), "\"blood_pct\":100"));
  AttentionInputs n; n.observed = false; CHECK(AttentionJson(n) == "{\"observed\":false}");
  AttentionInputs e; e.busyReason = ""; CHECK(!Has(AttentionJson(e), "busy_reason"));
  AttentionInputs u; u.busyReason = std::string("caf\xc3\xa9 shop"); CHECK(Has(AttentionJson(u), "\"busy_reason\":\"caf shop\""));
  CHECK(BloodPct(50, 100) == 50); CHECK(BloodPct(500, 100) == 100); CHECK(BloodPct(-3, 100) == 0); CHECK(BloodPct(10, 0) == -1);
  CHECK(HungerValue(0.5f, 0.2f) == 70); CHECK(HungerValue(5.f, 5.f) == 300); CHECK(HungerValue(-1.f, 0.f) == 0);
  CHECK(HungryFrom(74)); CHECK(!HungryFrom(75));
  CHECK(ExhaustedFrom(10, false)); CHECK(!ExhaustedFrom(40, false)); CHECK(ExhaustedFrom(200, true));
  CHECK(InjuredFrom(40, false, false, -1)); CHECK(InjuredFrom(100, true, false, -1)); CHECK(InjuredFrom(100, false, true, -1));
  CHECK(InjuredFrom(100, false, false, 60)); CHECK(!InjuredFrom(100, false, false, 90)); CHECK(!InjuredFrom(-1, false, false, -1));
}

static void TestAppend() {
  std::string attn = "{\"observed\":true}";
  CHECK(AppendAttention("{\"observed\":true,\"x\":1}", attn) == "{\"observed\":true,\"x\":1,\"attention\":{\"observed\":true}}");
  CHECK(AppendAttention("{\"observed\":false}", attn) == "{\"observed\":false}");
  CHECK(AppendAttention("", attn) == "");
  CHECK(AppendAttention("[]", attn) == "[]");
  CHECK(AppendAttention("{\"observed\":true,\"attention\":{}}", attn) == "{\"observed\":true,\"attention\":{}}");
  CHECK(AppendAttention("{\"observed\":true}  \n", attn) == "{\"observed\":true,\"attention\":{\"observed\":true}}");
  CHECK(AppendAttention("{\"observed\":true}", "") == "{\"observed\":true}");
}

static void TestPartner() {
  CHECK(ClassifyPartner(true, true, true, 10, true, true) == PS_NONE);
  CHECK(ClassifyPartner(false, true, false, 100, false, false) == PS_KNOCKED_OUT);
  CHECK(ClassifyPartner(false, false, true, 30, false, false) == PS_BLEEDING_OUT);
  CHECK(ClassifyPartner(false, false, false, 100, true, false) == PS_BLEEDING_OUT);
  CHECK(ClassifyPartner(false, false, true, 90, false, false) == PS_NONE);
  CHECK(ClassifyPartner(false, false, false, 100, false, true) == PS_DOWNED);
  CHECK(std::string(PartnerStateName(PS_BLEEDING_OUT)) == "bleeding_out");
}

// Feed observations every 2 s from..to inclusive; returns the time it fired or -1.
static double Run(AbandonTracker &t, unsigned l, unsigned p, bool free, int st, float d, double from, double to, AbandonEvent *ev) {
  for (double s = from; s <= to; s += 2) if (t.Observe(l, p, free, st, d, s, ev)) return s;
  return -1;
}
static void TestAbandon() {
  AbandonEvent ev;
  { // fires once after 20 s far, after having been close
    AbandonTracker t; double now = 1000;
    CHECK(!t.Observe(1, 2, true, PS_DOWNED, 10, now, &ev));
    bool fired = false; int fires = 0;
    for (int i = 1; i <= 40; ++i) { now += 2; if (t.Observe(1, 2, true, PS_DOWNED, 45, now, &ev)) { fired = true; ++fires; } }
    CHECK(fired); CHECK(fires == 1);
    CHECK(ev.evidenceId == "abandon:1:2:1000"); CHECK(ev.partnerState == "downed");
    CHECK(ev.seconds >= 20 && ev.seconds < 24); CHECK(ev.distanceM == 45);
  }
  { // no fire before 20 s
    AbandonTracker t; t.Observe(1, 2, true, PS_DOWNED, 5, 100, &ev);
    bool f = false; for (double s = 102; s <= 119; s += 1) f |= t.Observe(1, 2, true, PS_DOWNED, 50, s, &ev);
    CHECK(!f);
    CHECK(t.Observe(1, 2, true, PS_DOWNED, 50, 123, &ev));
  }
  { // never close -> unarmed leaver never fires
    AbandonTracker t; bool f = false;
    for (double s = 0; s < 200; s += 2) f |= t.Observe(1, 2, true, PS_DOWNED, 60, s, &ev);
    CHECK(!f);
  }
  { // 25..30 m does not arm; <30 resets the far timer
    AbandonTracker t; bool f = false; t.Observe(1, 2, true, PS_DOWNED, 27, 0, &ev);
    for (double s = 2; s < 100; s += 2) f |= t.Observe(1, 2, true, PS_DOWNED, 60, s, &ev);
    CHECK(!f);
    AbandonTracker u; u.Observe(1, 2, true, PS_DOWNED, 10, 0, &ev);
    u.Observe(1, 2, true, PS_DOWNED, 40, 2, &ev);
    u.Observe(1, 2, true, PS_DOWNED, 40, 12, &ev);
    CHECK(!u.Observe(1, 2, true, PS_DOWNED, 29, 14, &ev)); // within 30: resets
    CHECK(!u.Observe(1, 2, true, PS_DOWNED, 40, 16, &ev));
    CHECK(Run(u, 1, 2, true, PS_DOWNED, 40, 18, 34, &ev) < 0); // < 20 s since reset
    CHECK(Run(u, 1, 2, true, PS_DOWNED, 40, 36, 40, &ev) == 36);
  }
  { // scan gap > 10 s resets the timer
    AbandonTracker t; t.Observe(1, 2, true, PS_DOWNED, 10, 0, &ev);
    t.Observe(1, 2, true, PS_DOWNED, 40, 2, &ev);
    CHECK(!t.Observe(1, 2, true, PS_DOWNED, 40, 20, &ev)); // gap 18 s: restart
    CHECK(Run(t, 1, 2, true, PS_DOWNED, 40, 22, 38, &ev) < 0);
    CHECK(Run(t, 1, 2, true, PS_DOWNED, 40, 40, 44, &ev) == 40);
  }
  { // leaver incapacitated resets
    AbandonTracker t; t.Observe(1, 2, true, PS_DOWNED, 10, 0, &ev);
    t.Observe(1, 2, true, PS_DOWNED, 40, 2, &ev);
    CHECK(!t.Observe(1, 2, false, PS_DOWNED, 40, 12, &ev));
    CHECK(Run(t, 1, 2, true, PS_DOWNED, 40, 14, 32, &ev) < 0);
    CHECK(Run(t, 1, 2, true, PS_DOWNED, 40, 34, 38, &ev) == 34);
  }
  { // partner recovers: episode ends; next episode is fresh and needs re-arming
    AbandonTracker t; t.Observe(1, 2, true, PS_DOWNED, 10, 0, &ev);
    t.Observe(1, 2, true, PS_DOWNED, 40, 2, &ev);
    CHECK(Run(t, 1, 2, true, PS_DOWNED, 40, 4, 30, &ev) == 22);
    CHECK(!t.Observe(1, 2, true, PS_NONE, 40, 32, &ev));
    CHECK(!t.Observe(1, 2, true, PS_BLEEDING_OUT, 40, 100, &ev)); // second episode, never armed
    CHECK(!t.Observe(1, 2, true, PS_BLEEDING_OUT, 8, 102, &ev));  // arms
    CHECK(Run(t, 1, 2, true, PS_BLEEDING_OUT, 40, 104, 140, &ev) == 124);
    CHECK(ev.evidenceId == "abandon:1:2:100");
  }
  { // dedupe: fired pair does not fire again in the same episode; another leaver fires separately
    AbandonTracker t; t.Observe(1, 2, true, PS_DOWNED, 10, 0, &ev); t.Observe(3, 2, true, PS_DOWNED, 10, 0, &ev);
    t.Observe(1, 2, true, PS_DOWNED, 40, 2, &ev); t.Observe(3, 2, true, PS_DOWNED, 40, 2, &ev);
    bool a = false, b = false;
    for (double s = 4; s <= 26; s += 2) { a |= t.Observe(1, 2, true, PS_DOWNED, 40, s, &ev); b |= t.Observe(3, 2, true, PS_DOWNED, 40, s, &ev); }
    CHECK(a); CHECK(b);
    CHECK(Run(t, 1, 2, true, PS_DOWNED, 40, 28, 100, &ev) < 0);
  }
  { // time going backwards (reload) resets timers; self pair ignored
    AbandonTracker t; t.Observe(1, 2, true, PS_DOWNED, 10, 500, &ev);
    t.Observe(1, 2, true, PS_DOWNED, 40, 502, &ev);
    CHECK(!t.Observe(1, 2, true, PS_DOWNED, 40, 100, &ev));
    CHECK(!t.Observe(5, 5, true, PS_DOWNED, 40, 100, &ev));
  }
}

// N5b (row 13-b): a knocked-out partner cannot be the observer, so the proven abandonment is HELD by the tracker and
// released when the partner is conscious again (or after HoldSeconds if still alive); nothing is lost on dedupe.
static void TestAbandonHold() {
  AbandonEvent ev, got;
  { // KO partner: Observe never returns true; the event is pending, then released on wake with the episode state
    AbandonTracker t; double now = 1000; bool fired = false;
    CHECK(!t.Observe(1, 2, true, PS_KNOCKED_OUT, 10, now, &ev));
    for (int i = 1; i <= 40; ++i) { now += 2; fired |= t.Observe(1, 2, true, PS_KNOCKED_OUT, 45, now, &ev); }
    CHECK(!fired);
    CHECK(t.PendingCount() == 1);
    CHECK(t.PollPending(1, 2, true, true, false, now + 30, &got) == AbandonTracker::POLL_KEEP); // still KO
    CHECK(t.PendingCount() == 1);
    t.NotePartnerState(2, PS_NONE, now + 40); // partner woke: episode erased, pending survives
    CHECK(t.PendingCount() == 1);
    CHECK(t.PollPending(1, 2, true, true, true, now + 42, &got) == AbandonTracker::POLL_POST_WOKE);
    CHECK(got.evidenceId == "abandon:1:2:1000"); CHECK(got.partnerState == "knocked_out");
    CHECK(got.distanceM == 45); CHECK(got.seconds >= 20 && got.seconds < 24); CHECK(got.heldSec >= 60);
    CHECK(t.PendingCount() == 0);
    CHECK(t.PollPending(1, 2, true, true, true, now + 44, &got) == AbandonTracker::POLL_KEEP); // once only
    CHECK(!t.Observe(1, 2, true, PS_NONE, 45, now + 46, &ev));
  }
  { // wake while still hurt (downed): the held event is released with the episode's own state
    AbandonTracker t; double now = 0; t.Observe(1, 2, true, PS_KNOCKED_OUT, 10, now, &ev);
    for (int i = 1; i <= 15; ++i) { now += 2; t.Observe(1, 2, true, PS_KNOCKED_OUT, 50, now, &ev); }
    CHECK(t.PendingCount() == 1);
    CHECK(t.PollPending(1, 2, true, true, true, now + 2, &got) == AbandonTracker::POLL_POST_WOKE);
    CHECK(got.partnerState == "knocked_out");
  }
  { // bounded hold: after HoldSeconds a still-alive KO partner gets the event anyway; dead/absent partner drops it
    AbandonTracker t; double now = 100, fired = -1; t.Observe(1, 2, true, PS_KNOCKED_OUT, 10, now, &ev);
    for (int i = 1; i <= 15; ++i) { now += 2; t.Observe(1, 2, true, PS_KNOCKED_OUT, 50, now, &ev); if (fired < 0 && t.PendingCount()) fired = now; }
    CHECK(fired > 0);
    CHECK(AbandonTracker::HoldSeconds() > 60 && AbandonTracker::HoldSeconds() <= 1800);
    CHECK(t.PollPending(1, 2, true, true, false, fired + AbandonTracker::HoldSeconds() - 1, &got) == AbandonTracker::POLL_KEEP);
    CHECK(t.PollPending(1, 2, true, true, false, fired + AbandonTracker::HoldSeconds(), &got) == AbandonTracker::POLL_POST_TIMEOUT);
    CHECK(got.evidenceId == "abandon:1:2:100"); CHECK(t.PendingCount() == 0);
  }
  { // dead partner drops at once; absent (not loaded) pair is kept until the timeout, then dropped
    AbandonTracker t; double now = 0; t.Observe(1, 2, true, PS_KNOCKED_OUT, 10, now, &ev); t.Observe(3, 4, true, PS_KNOCKED_OUT, 10, now, &ev);
    for (int i = 1; i <= 15; ++i) { now += 2; t.Observe(1, 2, true, PS_KNOCKED_OUT, 50, now, &ev); t.Observe(3, 4, true, PS_KNOCKED_OUT, 50, now, &ev); }
    CHECK(t.PendingCount() == 2);
    CHECK(t.PollPending(1, 2, true, false, false, now + 1, &got) == AbandonTracker::POLL_DROP);
    CHECK(t.PendingCount() == 1);
    CHECK(t.PollPending(3, 4, false, false, false, now + 5, &got) == AbandonTracker::POLL_KEEP);
    CHECK(t.PollPending(3, 4, false, false, false, now + AbandonTracker::HoldSeconds() + 1, &got) == AbandonTracker::POLL_DROP);
    CHECK(t.PendingCount() == 0);
  }
  { // downed / bleeding partners are conscious: still fire immediately, nothing is held
    AbandonTracker t; double now = 0; t.Observe(1, 2, true, PS_BLEEDING_OUT, 10, now, &ev);
    bool f = false; for (int i = 1; i <= 15; ++i) { now += 2; f |= t.Observe(1, 2, true, PS_BLEEDING_OUT, 50, now, &ev); }
    CHECK(f); CHECK(ev.partnerState == "bleeding_out"); CHECK(t.PendingCount() == 0);
  }
  { // two leavers of one KO partner hold separately and release independently; Reset clears; clock going backwards times out
    AbandonTracker t; double now = 0; t.Observe(1, 2, true, PS_KNOCKED_OUT, 10, now, &ev); t.Observe(3, 2, true, PS_KNOCKED_OUT, 10, now, &ev);
    for (int i = 1; i <= 15; ++i) { now += 2; t.Observe(1, 2, true, PS_KNOCKED_OUT, 50, now, &ev); t.Observe(3, 2, true, PS_KNOCKED_OUT, 50, now, &ev); }
    CHECK(t.PendingCount() == 2);
    CHECK(t.PollPending(1, 2, true, true, true, now + 2, &got) == AbandonTracker::POLL_POST_WOKE); CHECK(got.evidenceId == "abandon:1:2:0");
    CHECK(t.PollPending(3, 2, true, true, true, now + 2, &got) == AbandonTracker::POLL_POST_WOKE); CHECK(got.evidenceId == "abandon:3:2:0");
    t.Observe(5, 6, true, PS_KNOCKED_OUT, 10, 0, &ev);
    for (int i = 1; i <= 15; ++i) t.Observe(5, 6, true, PS_KNOCKED_OUT, 50, i * 2.0, &ev);
    CHECK(t.PendingCount() == 1);
    CHECK(t.PollPending(5, 6, true, true, false, 5, &got) == AbandonTracker::POLL_POST_TIMEOUT); // now < held-at: reload
    t.NotePartnerState(6, PS_NONE, 90);
    t.Observe(5, 6, true, PS_KNOCKED_OUT, 10, 100, &ev);
    for (int i = 1; i <= 15; ++i) t.Observe(5, 6, true, PS_KNOCKED_OUT, 50, 100 + i * 2.0, &ev);
    CHECK(t.PendingCount() == 1); t.Reset(); CHECK(t.PendingCount() == 0);
  }
}

static void TestProximity() {
  { // load once: near on first scan -> fire after 8 s, only once
    ProximityGate g; bool f = false;
    CHECK(!g.OnScan(7, 100, true, 5, 80));
    CHECK(!g.OnScan(7, 104, true, 5, 80));
    CHECK(g.OnScan(7, 108.5, true, 5, 80));
    for (double s = 110; s < 5000; s += 2) f |= g.OnScan(7, s, true, 5, 80);
    CHECK(!f); // never again without being away
  }
  { // far at load: no load fire; away >= 45 s then return fires
    ProximityGate g;
    CHECK(!g.OnScan(7, 0, true, 100, 80));
    CHECK(!g.OnScan(7, 30, true, 100, 80));
    CHECK(!g.OnScan(7, 40, true, 10, 80)); // back before 45 s away
    CHECK(!g.OnScan(7, 42, true, 100, 80));
    CHECK(!g.OnScan(7, 80, true, 100, 80));
    CHECK(!g.OnScan(7, 88, true, 100, 80)); // 46 s away
    CHECK(g.OnScan(7, 90, true, 12, 80));
    CHECK(!g.OnScan(7, 92, true, 12, 80));
  }
  { // not idle: no fire, away stays armed until idle
    ProximityGate g; g.OnScan(7, 0, true, 100, 80); g.OnScan(7, 50, true, 100, 80);
    CHECK(!g.OnScan(7, 52, false, 10, 80)); CHECK(g.OnScan(7, 54, true, 10, 80));
  }
  { // talk radius below 15 caps the near radius
    ProximityGate g; g.OnScan(7, 0, true, 100, 6); g.OnScan(7, 50, true, 100, 6);
    CHECK(!g.OnScan(7, 52, true, 10, 6)); CHECK(g.OnScan(7, 54, true, 5, 6));
    CHECK(ProximityGate::NearRadius(80) == 15.0f); CHECK(ProximityGate::NearRadius(6) == 6.0f);
  }
  { // global 90 s and per-NPC 10 min limits
    ProximityGate g;
    CHECK(g.TryFire(1, 1000)); CHECK(!g.TryFire(2, 1050)); CHECK(g.TryFire(2, 1091));
    CHECK(!g.TryFire(1, 1500)); CHECK(g.TryFire(1, 1692));
    CHECK(!g.TryFire(1, 1700));
  }
  { // combat trigger: delay, range, stale, one pending
    ProximityGate g;
    g.NoteCombatStart(10, 80); CHECK(!g.CombatPending());
    g.NoteCombatStart(10, 30); CHECK(g.CombatPending());
    g.NoteCombatStart(11, 30);
    CHECK(!g.TakeCombatDue(11)); CHECK(g.TakeCombatDue(11.6)); CHECK(!g.TakeCombatDue(12));
    g.NoteCombatStart(20, 30); CHECK(!g.TakeCombatDue(40)); CHECK(!g.CombatPending()); // stale: dropped
  }
  { // reset clears everything
    ProximityGate g; g.TryFire(1, 100); g.NoteCombatStart(0, 1); g.Reset();
    CHECK(!g.CombatPending()); CHECK(g.TryFire(1, 101));
  }
}

int main() {
  TestAttention(); TestAppend(); TestPartner(); TestAbandon(); TestAbandonHold(); TestProximity();
  std::cout << "N2 logic tests: " << g_pass << " passed, " << g_fail << " failed\n";
  return g_fail ? 1 : 0;
}
