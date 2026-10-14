#!/usr/bin/env python3
"""Mocked parser/contract tests for P0-TRAVEL-REGION-CONSENT-ROUTE-001; no rig calls."""
import importlib.util
import hashlib
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("region_consent_route", HERE / "region-consent-route.py")
row = importlib.util.module_from_spec(spec)
spec.loader.exec_module(row)
cases = []


def check(name, fn):
    try:
        fn()
    except Exception as exc:
        raise AssertionError(f"{name}: {exc}") from exc
    cases.append(name)


def rejects(name, fn, reason=None):
    try:
        fn()
    except row.Stop as exc:
        if reason and reason not in exc.why:
            raise AssertionError(f"{name}: wrong rejection {exc.why!r}")
        cases.append(name)
        return
    raise AssertionError(f"{name}: expected fail-closed Stop")


req = "k1712345678901_22_1"
proposal_msg = "Would you suggest Mourn as a broad area for a trip? I am only asking whether you would offer that rough area; I am not agreeing to travel yet."
accept_msg = "I agree to go to Mourn as a broad area."
row.ROW = "P0-TRAVEL-REGION-CONSENT-ROUTE-001"
row.NPC, row.SERIAL, row.SPEAKER, row.REGION = "Laru [Trader]", "1234", "Shay", "Mourn"
row.integration_endpoint_source = "current_actor_scoped_native_candidate"
row.trip_scope_expected = {"campaign_id": 10, "actor_id": 1234, "speaker_id": 5678}
scope_hash = hashlib.sha256(json.dumps(row.trip_scope_expected, separators=(",", ":")).encode()).hexdigest()


def backend(message, decision="PROPOSE", **changes):
    rec = {"native_request_id": req, "row_id": row.ROW, "npc_name": row.NPC,
           "npc_serial": 1234, "speaker": row.SPEAKER, "player_message": message,
           "travel_decision": decision,
           "destination_point": {"id": "local:world:2543823360:77", "label": "Mourn approach",
                                 "actor_serial": 1234, "source": "native_local", "x": 100.0, "y": 0.0, "z": 0.0},
           "regional_goal": {"region": "Mourn", "endpoint_id": "local:world:2543823360:77",
                             "endpoint_label": "Mourn approach", "endpoint_actor_serial": 1234,
                             "endpoint_source": "current_actor_scoped_native_candidate",
                             "endpoint_region_evidence": "npc_known_town_region",
                             "ordinary_order_validation": "passed", "order_validation_gamets": 1001,
                             "trip_read_gamets": 1000,
                             "trip_read_succeeded": True, "prior_trip_status": "none",
                             "trip_read_actor_serial": 1234, "trip_read_speaker_serial": 5678,
                             "trip_read_scope": dict(row.trip_scope_expected), "trip_read_scope_hash": scope_hash}}
    rec.update(changes)
    return rec


def endpoint(record=None, spoken=None):
    return row.endpoint_from_proposal(record or backend(accept_msg, "ACCEPT"), spoken or
                                      "Agreed. I can lead us toward Mourn using Mourn approach as a rough starting point; "
                                      "I cannot promise the full route is safe or what we will find.")


def sample(pos, dest=(100.0, 0.0, 0.0), moving=True, reached=False, failed=False):
    return {"pos": tuple(pos), "destination": tuple(dest), "moving": moving,
            "reached": reached, "failed": failed, "name": row.NPC, "serial": 1234}


check("complete_stream_marker", lambda: (_ for _ in ()).throw(AssertionError())
      if row.complete("CHAT_THREAD: Queued 1 streamed chat lines and 0 action lines") != (1, 0) else None)
check("request_id_exact_submission", lambda: (_ for _ in ()).throw(AssertionError())
      if row.request_id(f"TEST_INBOX: say id={req} mode=chat speaker=Shay target={row.NPC} text={proposal_msg}",
                        row.SPEAKER, row.NPC, proposal_msg) != req else None)
check("request_id_rejects_unrelated_message", lambda: (_ for _ in ()).throw(AssertionError())
      if row.request_id(f"TEST_INBOX: say id={req} mode=chat speaker=Shay target={row.NPC} text=other",
                        row.SPEAKER, row.NPC, proposal_msg) is not None else None)
check("preconsent_no_dispatch", lambda: (_ for _ in ()).throw(AssertionError())
      if not row.preconsent_no_action("CHAT_THREAD: Queued 1 streamed chat lines and 0 action lines\nNPC_SAY: Laru [Trader]|1234: proposal", 0) else None)
rejects("preconsent_action_rejected", lambda: row.preconsent_no_action("ACTION_EXEC: TRAVEL_LOCATION serial=1234", 1) or row.stop("product", "pre-consent dispatch"))

records = row.correlated(__import__("json").dumps(backend(proposal_msg, "NONE", region_plan_decision="SUGGEST",
                                                           proposed_region="Mourn")), req, {"message": proposal_msg})
check("backend_exact_proposal_correlated", lambda: (_ for _ in ()).throw(AssertionError())
      if len(records) != 1 or records[0][1] != "NONE" else None)
check("proposal_requires_explicit_none", lambda: row.require_proposal_none("NONE"))
rejects("proposal_missing_travel_decision_rejected", lambda: row.require_proposal_none(None))
rejects("proposal_blank_travel_decision_rejected", lambda: row.require_proposal_none(" "))
rejects("proposal_dispatch_decision_rejected", lambda: row.require_proposal_none("ACCEPT"))
check("region_suggestion_bound", lambda: (_ for _ in ()).throw(AssertionError())
      if row.val({k.casefold(): [v] for k, v in records[0][0].items()}, "region_plan_decision") != "SUGGEST"
      or row.val({k.casefold(): [v] for k, v in records[0][0].items()}, "proposed_region") != "Mourn" else None)
accept_record = backend(accept_msg, "ACCEPT")
check("scoped_no_active_trip_proof", lambda: (_ for _ in ()).throw(AssertionError())
      if not row.no_active_trip_proof(accept_record, 1234, row.SPEAKER) else None)
rejects("trip_read_failure_not_treated_empty", lambda: row.stop("evidence", "read failed")
        if not row.no_active_trip_proof(backend(accept_msg, "ACCEPT", regional_goal={}), 1234, row.SPEAKER) else None)
rejects("other_actor_trip_state_rejected", lambda: row.stop("evidence", "scope mismatch")
        if not row.no_active_trip_proof(backend(accept_msg, "ACCEPT", regional_goal={"trip_read_succeeded": True,
            "prior_trip_status": "none", "trip_read_actor_serial": 999, "trip_read_speaker_serial": 5678,
            "trip_read_scope": dict(row.trip_scope_expected), "trip_read_scope_hash": scope_hash}), 1234, row.SPEAKER) else None)
rejects("active_trip_state_rejected", lambda: row.stop("evidence", "active trip")
        if not row.no_active_trip_proof(backend(accept_msg, "ACCEPT", regional_goal={"trip_read_succeeded": True,
            "prior_trip_status": "RUNNING", "trip_read_actor_serial": 1234, "trip_read_speaker_serial": 5678,
            "trip_read_scope": dict(row.trip_scope_expected), "trip_read_scope_hash": scope_hash}), 1234, row.SPEAKER) else None)
rejects("missing_trip_status_rejected", lambda: row.stop("evidence", "status missing")
        if not row.no_active_trip_proof(backend(accept_msg, "ACCEPT", regional_goal={"trip_read_succeeded": True,
            "trip_read_actor_serial": 1234, "trip_read_speaker_serial": 5678,
            "trip_read_scope": dict(row.trip_scope_expected), "trip_read_scope_hash": scope_hash}), 1234, row.SPEAKER) else None)
rejects("missing_trip_scope_rejected", lambda: row.stop("evidence", "scope missing")
        if not row.no_active_trip_proof(backend(accept_msg, "ACCEPT", regional_goal={"trip_read_succeeded": True,
            "prior_trip_status": "none", "trip_read_actor_serial": 1234, "trip_read_speaker_serial": 5678,
            "trip_read_scope_hash": scope_hash}), 1234, row.SPEAKER) else None)
rejects("wrong_trip_scope_hash_rejected", lambda: row.stop("evidence", "scope hash mismatch")
        if not row.no_active_trip_proof(backend(accept_msg, "ACCEPT", regional_goal={"trip_read_succeeded": True,
            "prior_trip_status": "none", "trip_read_actor_serial": 1234, "trip_read_speaker_serial": 5678,
            "trip_read_scope": dict(row.trip_scope_expected), "trip_read_scope_hash": "0" * 64}), 1234, row.SPEAKER) else None)
reordered_scope = {"actor_id": 1234, "campaign_id": 10, "speaker_id": 5678}
rejects("trip_scope_hash_order_mismatch_rejected", lambda: row.stop("evidence", "order/hash mismatch")
        if not row.no_active_trip_proof(backend(accept_msg, "ACCEPT", regional_goal={"trip_read_succeeded": True,
            "prior_trip_status": "none", "trip_read_actor_serial": 1234, "trip_read_speaker_serial": 5678,
            "trip_read_scope": reordered_scope, "trip_read_scope_hash": scope_hash}), 1234, row.SPEAKER) else None)
for label, changes in (("wrong_request", {"native_request_id": "k9999999999999_1_1"}),
                       ("wrong_row", {"row_id": "other"}), ("wrong_actor", {"npc_name": "Other"}),
                       ("wrong_serial", {"npc_serial": 999}), ("wrong_speaker", {"speaker": "Other"}),
                       ("wrong_message", {"player_message": "different"})):
    rejects(f"backend_{label}_uncorrelated", lambda changes=changes:
            row.stop("evidence", "missing") if not row.correlated(__import__("json").dumps(backend(proposal_msg, "NONE", **changes)), req,
                                                                    {"message": proposal_msg}) else None)

ep = endpoint()
check("native_adapter_endpoint_bound", lambda: (_ for _ in ()).throw(AssertionError())
      if ep != {"id": "local:world:2543823360:77", "label": "Mourn approach", "region": "Mourn",
                "source": "current_actor_scoped_native_candidate", "xyz": (100.0, 0.0, 0.0)} else None)
for label, changes in (("wrong_region", {"endpoint_region": "The Hub"}),
                       ("wrong_actor_endpoint", {"endpoint_actor_serial": 999}),
                       ("unknown_source", {"endpoint_source": "hardcoded_catalog"}),
                       ("missing_region_evidence", {"endpoint_region_evidence": None}),
                       ("missing_order_validation", {"ordinary_order_validation": None}),
                       ("missing_trip_read_time", {"trip_read_gamets": None}),
                       ("missing_xyz", {"x": None, "y": None, "z": None})):
    def altered_endpoint(changes=changes):
        rec = backend(accept_msg, "ACCEPT")
        for key, value in changes.items():
            if key == "endpoint_region":
                rec["regional_goal"]["region"] = value
            elif key == "endpoint_actor_serial":
                rec["destination_point"]["actor_serial"] = value
                rec["regional_goal"]["endpoint_actor_serial"] = value
            elif key == "endpoint_source":
                rec["regional_goal"]["endpoint_source"] = value
            elif key == "endpoint_region_evidence":
                rec["regional_goal"]["endpoint_region_evidence"] = value
            elif key == "ordinary_order_validation":
                rec["regional_goal"]["ordinary_order_validation"] = value
            elif key == "trip_read_gamets":
                rec["regional_goal"]["trip_read_gamets"] = value
            else:
                rec["destination_point"][key[0]] = value
        endpoint(rec)
    rejects(f"endpoint_{label}_rejected", altered_endpoint)
rejects("proposal_must_name_bound_endpoint", lambda: endpoint(backend(accept_msg, "ACCEPT"), "I can lead you somewhere."))

row.NPC, row.SERIAL = "Laru [Trader]", "1234"
event = "ACTION_EXEC: TRAVEL_LOCATION actor=Laru [Trader] destination='Mourn approach' x=100 y=0 z=0 serial=1234"
check("native_action_exact_actor_serial_label", lambda: (_ for _ in ()).throw(AssertionError())
      if row.event_matches(event, ep) != (100.0, 0.0, 0.0) else None)
for label, bad in (("wrong_actor", event.replace("actor=Laru [Trader]", "actor=Other")),
                   ("wrong_label", event.replace("Mourn approach", "Stack")),
                   ("wrong_serial", event.replace("serial=1234", "serial=999")),
                   ("malformed_xyz", event.replace("x=100 y=0 z=0", "x=? y=0 z=0")),
                   ("dot_xyz", event.replace("x=100", "x=.")),
                   ("incomplete_exponent_xyz", event.replace("x=100", "x=1e")),
                   ("missing_xyz", event.replace(" x=100 y=0 z=0", ""))):
    check(f"native_action_{label}_fails", lambda bad=bad: (_ for _ in ()).throw(AssertionError())
          if row.event_matches(bad, ep) is not None else None)
check("native_action_wrong_xyz_rejected", lambda: (_ for _ in ()).throw(AssertionError())
      if row.event_matches(event.replace("x=100", "x=102"), ep) is not None else None)
check("consent_action_follows_exact_request", lambda: (_ for _ in ()).throw(AssertionError())
      if not row.actions_follow_exact_request(
          f"TEST_INBOX: say id={req} mode=chat speaker=Shay target={row.NPC} text={accept_msg}\n{event}", req) else None)
check("action_before_consent_request_detected", lambda: (_ for _ in ()).throw(AssertionError())
      if row.actions_follow_exact_request(
          f"{event}\nTEST_INBOX: say id={req} mode=chat speaker=Shay target={row.NPC} text={accept_msg}", req) else None)

good_samples = [sample((0, 0, 0)), sample((6, 0, 0)), sample((12, 0, 0))]
check("same_actor_two_interval_progress", lambda: row.validate_progress_samples(good_samples, {"xyz": (100, 0, 0)}, (0, 0, 0)))
rejects("no_progress_rejected", lambda: row.validate_progress_samples(
    [sample((0, 0, 0)), sample((0.1, 0, 0)), sample((0.2, 0, 0))], {"xyz": (100, 0, 0)}, (0, 0, 0)))
rejects("wrong_native_destination_rejected", lambda: row.validate_progress_samples(
    [sample((0, 0, 0), dest=(200, 0, 0)), sample((6, 0, 0), dest=(200, 0, 0)), sample((12, 0, 0), dest=(200, 0, 0))],
    {"xyz": (100, 0, 0)}, (0, 0, 0)))
rejects("native_path_failure_rejected", lambda: row.validate_progress_samples(
    [sample((0, 0, 0)), sample((6, 0, 0)), sample((12, 0, 0), failed=True)], {"xyz": (100, 0, 0)}, (0, 0, 0)))
rejects("missing_path_failed_state_rejected", lambda: row.validate_progress_samples(
    [sample((0, 0, 0)), sample((6, 0, 0)), {**sample((12, 0, 0)), "failed": None}],
    {"xyz": (100, 0, 0)}, (0, 0, 0)))
rejects("missing_moving_state_rejected", lambda: row.validate_progress_samples(
    [sample((0, 0, 0)), {**sample((6, 0, 0)), "moving": None}, sample((12, 0, 0))],
    {"xyz": (100, 0, 0)}, (0, 0, 0)))
rejects("nonnumeric_native_destination_rejected", lambda: row.finite_vector(["bad", 0, 0], "mock native destination"))
rejects("nonfinite_native_destination_rejected", lambda: row.validate_progress_samples(
    [sample((0, 0, 0), dest=(math.nan, 0, 0)), sample((6, 0, 0)), sample((12, 0, 0))],
    {"xyz": (100, 0, 0)}, (0, 0, 0)))
rejects("infinite_native_position_rejected", lambda: row.validate_progress_samples(
    [sample((0, 0, 0)), sample((math.inf, 0, 0)), sample((12, 0, 0))],
    {"xyz": (100, 0, 0)}, (0, 0, 0)))
rejects("no_native_moving_state_rejected", lambda: row.validate_progress_samples(
    [sample((0, 0, 0), moving=False), sample((6, 0, 0), moving=False), sample((12, 0, 0), moving=False)],
    {"xyz": (100, 0, 0)}, (0, 0, 0)))

contract = {"candidate_sha256": "A" * 64, "review_status": "CLEAR", "installed": True, "served": True,
            "integration_build_sha256": "B" * 64, "movement_consent_contract": "one_coarse_region_acceptance",
            "endpoint_requires_separate_consent": False, "preconsent_proposal_only": True,
            "endpoint_proof_source": "current_actor_scoped_native_candidate"}
check("exact_current_integration_contract", lambda: row.validate_integration_contract(contract, "B" * 64, "A" * 64))
rejects("uninstalled_candidate_blocked", lambda: row.validate_integration_contract(
    dict(contract, installed=False), "B" * 64, "A" * 64))
rejects("wrong_loaded_build_blocked", lambda: row.validate_integration_contract(contract, "C" * 64, "A" * 64))
rejects("endpoint_specific_consent_semantics_blocked", lambda: row.validate_integration_contract(
    dict(contract, endpoint_requires_separate_consent=True), "B" * 64, "A" * 64))

if "Mourn" not in accept_msg or "Mourn approach" in accept_msg:
    raise AssertionError("single consent must accept the coarse region without naming/accepting the exact endpoint")
cases.append("one_region_consent_not_endpoint_consent")
print(f"SELFTEST PASS mocked_cases={len(cases)} row={row.ROW} cases={','.join(cases)}")
