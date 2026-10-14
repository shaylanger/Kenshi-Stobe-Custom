#!/usr/bin/env python3
"""Mocked end-to-end handler flow for driver.sh; no game or rig access."""
import os
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
BASH = os.environ.get("TRAVEL_DRIVER_BASH", r"C:\Program Files\Git\bin\bash.exe")
NPC = "Cind [Hungry Bandit]"


def run(mode="success"):
    with tempfile.TemporaryDirectory(prefix=".travel-driver-mock-", dir=HERE) as td:
        root = Path(td)
        bindir = root / "bin"
        bindir.mkdir()
        log = root / "stobe.log"
        log.write_text("baseline\n", encoding="utf-8")
        marker = root / "accept.sent"
        (bindir / "stobe-auto").write_text(r'''#!/usr/bin/env bash
touch "$KAH_CALL_MARKER"
case "$1" in
 status) echo 'phase=world save=fixture speed=1.0' ;;
 towns) echo 'Heft pos=100,0,0 distance=100';;
 where)
   n=0; [[ -f "$WHERE_COUNT" ]] && n=$(cat "$WHERE_COUNT"); n=$((n+1)); echo "$n" >"$WHERE_COUNT"
   x=0; if [[ ("$MOCK_MODE" == success || "$MOCK_MODE" == no_tick || "$MOCK_MODE" == position_only || "$MOCK_MODE" == multi_offer) && "$n" -ge 3 ]]; then x=$(((n-2)*10)); [[ "$x" -gt 40 ]] && x=40; fi
   [[ "$MOCK_MODE" == incidental_wander && "$n" -ge 3 ]] && x=0.02
   [[ "$MOCK_MODE" == drift_before_start && "$n" -ge 2 ]] && x=40
   d=10; [[ "$MOCK_MODE" == range_wander && "$n" -ge 2 ]] && d=90
   echo "Cind [Hungry Bandit] #123/1 pos=$x,0,0 dist=$d" ;;
 stobe_state)
   orders=false; goal=NULL_TASK; moving=false
   [[ -f "$ACCEPT_MARKER" ]] && { goal=OTHER; moving=true; }
   [[ "$MOCK_MODE" == changed_goal && -f "$ACCEPT_MARKER" ]] && { goal=OTHER; moving=false; }
   [[ "$MOCK_MODE" == position_only && -f "$ACCEPT_MARKER" ]] && { goal=OTHER; moving=false; }
   path_failed=false; [[ "$MOCK_MODE" == path_failed ]] && path_failed=true
   dx=100; [[ "$MOCK_MODE" == destination_mismatch ]] && dx=80
   printf '{"name":"Cind [Hungry Bandit]","serial":123,"ai":{"dead":false,"unconscious":false,"can_take_orders":true,"has_orders":%s,"has_player_orders":false,"first_order":"none","current_goal":"%s","moving":%s,"destination_reached":false,"path_failed":%s,"destination":[%s,0,0]}}\n' "$orders" "$goal" "$moving" "$path_failed" "$dx" ;;
 stobe_say)
   n=0; [[ -f "$SAY_COUNT" ]] && n=$(cat "$SAY_COUNT"); n=$((n+1)); echo "$n" >"$SAY_COUNT"
   if [[ $n == 1 ]]; then
     if [[ "$MOCK_MODE" == multi_offer || "$MOCK_MODE" == multi_decline ]]; then
       echo 'CHAT_THREAD: Queued 2 streamed chat lines and 0 action lines.' >>"$NATIVE_LOG"
       echo 'NPC_SAY: Cind [Hungry Bandit]|123: Heft lies far to the east.' >>"$NATIVE_LOG"
       if [[ "$MOCK_MODE" == multi_offer ]]; then
         (sleep 0.1; echo 'NPC_SAY: Cind [Hungry Bandit]|123: I can guide you to Heft.' >>"$NATIVE_LOG") &
       else
         (sleep 0.1; echo "NPC_SAY: Cind [Hungry Bandit]|123: I don't lead people to Heft." >>"$NATIVE_LOG") &
       fi
     else
       echo 'CHAT_THREAD: Queued 1 streamed chat lines and 0 action lines.' >>"$NATIVE_LOG"
       case "$MOCK_MODE" in
         wrong_speaker|unrelated_name) echo 'NPC_SAY: Other NPC|456: Cind [Hungry Bandit] says I can guide you to Heft.' >>"$NATIVE_LOG" ;;
         refusal_dont) echo "NPC_SAY: Cind [Hungry Bandit]|123: I don't lead people to Heft." >>"$NATIVE_LOG" ;;
         refusal_never) echo 'NPC_SAY: Cind [Hungry Bandit]|123: I would never guide you to Heft.' >>"$NATIVE_LOG" ;;
         conditional) echo 'NPC_SAY: Cind [Hungry Bandit]|123: I could guide you to Heft.' >>"$NATIVE_LOG" ;;
         conditional_if) echo 'NPC_SAY: Cind [Hungry Bandit]|123: I can guide you to Heft if you pay me.' >>"$NATIVE_LOG" ;;
         deferred) echo 'NPC_SAY: Cind [Hungry Bandit]|123: I can lead you to Heft, but not today.' >>"$NATIVE_LOG" ;;
         no_offer) echo 'NPC_SAY: Cind [Hungry Bandit]|123: Heft is far away.' >>"$NATIVE_LOG" ;;
         serial_in_speech) echo 'NPC_SAY: Other NPC|456: Cind [Hungry Bandit]|123: I can guide you to Heft.' >>"$NATIVE_LOG" ;;
         *) echo 'NPC_SAY: Cind [Hungry Bandit]|123: I can guide you to Heft.' >>"$NATIVE_LOG" ;;
       esac
     fi
     if [[ "$MOCK_MODE" == early_start ]]; then echo 'ACTION_EXEC: TRAVEL_LOCATION serial=123 destination=Heft endpoint=100,0,0' >>"$NATIVE_LOG"; fi
     if [[ "$MOCK_MODE" == stale_tick ]]; then echo "TRAVEL_TICK: actor=Cind [Hungry Bandit] destination='Heft' status=stale" >>"$NATIVE_LOG"; fi
   elif [[ "$MOCK_MODE" != no_start ]]; then
     touch "$ACCEPT_MARKER"
     if [[ "$MOCK_MODE" == serial_only_coords ]]; then
       echo 'ACTION_EXEC: TRAVEL_LOCATION target=999 coordinates=123,0,0 endpoint=100,0,0' >>"$NATIVE_LOG"
     elif [[ "$MOCK_MODE" == wrong_action_serial ]]; then
       echo 'ACTION_EXEC: TRAVEL_LOCATION serial=999 actor=123 endpoint=100,0,0' >>"$NATIVE_LOG"
     else
       echo 'ACTION_EXEC: TRAVEL_LOCATION serial=123 destination=Heft endpoint=100,0,0' >>"$NATIVE_LOG"
     fi
     if [[ "$MOCK_MODE" == duplicate_start ]]; then (sleep 0.1; echo 'ACTION_EXEC: TRAVEL_LOCATION serial=123 destination=Heft endpoint=100,0,0' >>"$NATIVE_LOG") & fi
     if [[ "$MOCK_MODE" != no_tick && "$MOCK_MODE" != stale_tick ]]; then echo "TRAVEL_TICK: actor=Cind [Hungry Bandit] destination='Heft' status=walking" >>"$NATIVE_LOG"; fi
   fi ;;
 *) exit 2 ;;
esac
''', encoding="utf-8")
        (bindir / "stobe-auto").chmod(0o755)
        (bindir / "python3").write_text("#!/usr/bin/env bash\nscript=$(cygpath -w \"$1\"); shift; exec python \"$script\" \"$@\"\n", encoding="utf-8")
        (bindir / "python3").chmod(0o755)
        destination = root / "destination.receipt"
        preflight = root / "preflight.receipt"
        out = root / "out"
        if mode == "existing_out":
            out.mkdir()
        destination.write_text("Fresh native route receipt\n", encoding="utf-8")
        preflight.write_text("Fresh copied save/build/backend/session/isolation receipt\n", encoding="utf-8")
        env = os.environ.copy()
        env.update({"PATH": str(bindir) + os.pathsep + env.get("PATH", ""), "TRAVEL_DRIVER_BASH": BASH, "MSYS_NO_PATHCONV": "1",
                    "RIG": "5090", "KAH_INSTANCE": "3", "KENSHI_DIR": "/mnt/d/KenshiInst/3",
                    "KAH_DIR": r"D:\KenshiInst\3\mods\AutomationHarness", "NPC": "Cind" if mode == "alias_name" else NPC,
                    "TRAVEL_DESTINATION": "Heft", "DESTINATION_RECEIPT": str(destination),
                    "PREFLIGHT_RECEIPT": str(preflight), "OUT": str(out),
                    "NATIVE_LOG": str(log), "WAIT_SECONDS": "1", "POLL_SECONDS": "0.01", "START_SETTLE_SECONDS": "0.2",
                    "SAY_COUNT": str(root / "say-count"), "WHERE_COUNT": str(root / "where-count"),
                    "ACCEPT_MARKER": str(marker), "KAH_CALL_MARKER": str(root / "kah.called"), "MOCK_MODE": mode})
        p = subprocess.run([BASH, str(HERE / "driver.sh")], env=env, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        p.stdout += f"\nMOCK kah_called={(root / 'kah.called').exists()} accept_sent={marker.exists()} native_actions={sum('TRAVEL_LOCATION' in line for line in log.read_text(encoding='utf-8').splitlines())}"
        return p


success = run()
assert success.returncode == 0 and "PASS-START-MOVE" in success.stdout, success.stdout
for mode in ("refusal_dont", "refusal_never"):
    declined = run(mode)
    assert declined.returncode == 0 and "PASS-DECLINED" in declined.stdout and "accept_sent=False native_actions=0" in declined.stdout, declined.stdout
ambiguous = run("conditional")
assert ambiguous.returncode == 3 and "completed target response was ambiguous" in ambiguous.stdout and "accept_sent=False native_actions=0" in ambiguous.stdout, ambiguous.stdout
conditional_if = run("conditional_if")
assert conditional_if.returncode == 3 and "completed target response was ambiguous" in conditional_if.stdout and "accept_sent=False native_actions=0" in conditional_if.stdout, conditional_if.stdout
deferred = run("deferred")
assert deferred.returncode == 3 and "completed target response was ambiguous" in deferred.stdout and "accept_sent=False native_actions=0" in deferred.stdout, deferred.stdout
no_offer = run("no_offer")
assert no_offer.returncode == 3 and "completed target response was ambiguous" in no_offer.stdout and "accept_sent=False native_actions=0" in no_offer.stdout, no_offer.stdout
alias = run("alias_name")
assert alias.returncode == 2 and "exact actor/serial/position/native player distance" in alias.stdout and "accept_sent=False native_actions=0" in alias.stdout, alias.stdout
for mode in ("wrong_speaker", "unrelated_name", "serial_in_speech"):
    bad_speaker = run(mode)
    assert bad_speaker.returncode == 3 and "no exact target-speaker reply" in bad_speaker.stdout and "accept_sent=False native_actions=0" in bad_speaker.stdout, bad_speaker.stdout
no_start = run("no_start")
assert no_start.returncode == 3 and "no native TRAVEL_LOCATION" in no_start.stdout, no_start.stdout
for mode in ("serial_only_coords", "wrong_action_serial"):
    bad_action = run(mode)
    assert bad_action.returncode == 3 and "no native TRAVEL_LOCATION" in bad_action.stdout, bad_action.stdout
early_start = run("early_start")
assert early_start.returncode == 4 and "appeared before player acceptance" in early_start.stdout, early_start.stdout
no_movement = run("no_movement")
assert no_movement.returncode == 3 and "no repeated directional movement proof" in no_movement.stdout, no_movement.stdout
drift = run("drift_before_start")
assert drift.returncode == 3 and "no repeated directional movement proof" in drift.stdout, drift.stdout
incidental = run("incidental_wander")
assert incidental.returncode == 3 and "no repeated directional movement proof" in incidental.stdout, incidental.stdout
position_only = run("position_only")
assert position_only.returncode == 3 and "no repeated directional movement proof" in position_only.stdout, position_only.stdout
destination_mismatch = run("destination_mismatch")
assert destination_mismatch.returncode == 3 and "ai.destination is missing or differs" in destination_mismatch.stdout, destination_mismatch.stdout
stale_tick = run("stale_tick")
assert stale_tick.returncode == 3 and "no repeated directional movement proof" in stale_tick.stdout, stale_tick.stdout
changed_goal = run("changed_goal")
assert changed_goal.returncode == 3 and "no repeated directional movement proof" in changed_goal.stdout, changed_goal.stdout
path_failed = run("path_failed")
assert path_failed.returncode == 3 and "state contradicts successful movement" in path_failed.stdout, path_failed.stdout
duplicate_start = run("duplicate_start")
assert duplicate_start.returncode == 4 and ("duplicate matching native TRAVEL_LOCATION start" in duplicate_start.stdout or "expected exactly one matching native TRAVEL_LOCATION start, observed 2" in duplicate_start.stdout), duplicate_start.stdout
range_wander = run("range_wander")
assert range_wander.returncode == 2 and "wandered outside native chat radius before acceptance" in range_wander.stdout and "accept_sent=False native_actions=0" in range_wander.stdout, range_wander.stdout
no_tick = run("no_tick")
assert no_tick.returncode == 0 and "PASS-START-MOVE" in no_tick.stdout and "movement_tick=unavailable_optional" in no_tick.stdout, no_tick.stdout
multi_offer = run("multi_offer")
assert multi_offer.returncode == 0 and "PASS-START-MOVE" in multi_offer.stdout, multi_offer.stdout
multi_decline = run("multi_decline")
assert multi_decline.returncode == 0 and "PASS-DECLINED" in multi_decline.stdout and "accept_sent=False native_actions=0" in multi_decline.stdout, multi_decline.stdout
existing_out = run("existing_out")
assert existing_out.returncode == 2 and "output directory already exists" in existing_out.stdout and "kah_called=False accept_sent=False native_actions=0" in existing_out.stdout, existing_out.stdout
print("SELFTEST PASS mocked_cases=28 lifecycle=3 declined_no_accept=3 ambiguous_conditional_no_accept=3 exact_display_alias_rejected=1 wrong_speaker_name_serial=3 no_start=1 action_serial_guards=2 preaccept_start=1 no_movement=1 proposal_motion_only=1 incidental_wander_rejected=1 moving_false_rejected=1 destination_mismatch_rejected=1 stale_tick_ignored=1 goal_other_orders_false_moving_true=1 explicit_path_failure_rejected=1 duplicate_start=1 range_wander_no_accept=1 tick_optional=1 stream_segments_accumulated=2 existing_output_atomic_rejected_before_kah=1")
