#!/usr/bin/env python3
"""Targeted final-utterance protocol regressions; no game or rig access."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("role_driver", HERE / "driver.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)

partial = """CHAT_THREAD: Queued 2 streamed chat lines and 0 action lines.
NPC_SAY: Cind [Hungry Bandit]|2529907200: Lead the way to The Hub.
NPC_SAY: Cind [Hungry Bandit]|2529907200: I've got the route mapped.
NPC_SAY: Cind [Hungry Bandit]|2529907200: Lead the way to The Hub. [TALKTARGET:id] [UTTERANCEID:utt-a]
"""
records, conflict = driver.final_speech_records(partial)
assert len(records) == 1 and not conflict
assert driver.streamed_speech_count(partial) == 1  # Two provisional lines cannot complete Queued 2.

actual_format = partial + "NPC_SAY: Cind [Hungry Bandit]|2529907200: I've got the route mapped. [TALKTARGET:id] [UTTERANCEID:utt-b]\n"
records, conflict = driver.final_speech_records(actual_format)
assert len(records) == 2 and not conflict
assert driver.streamed_speech_count(actual_format) == 2  # Two provisional + two final = two utterances.

duplicate = actual_format + "NPC_SAY: Cind [Hungry Bandit]|2529907200: Lead the way to The Hub. [TALKTARGET:id] [UTTERANCEID:utt-a]\n"
assert driver.streamed_speech_count(duplicate) == 2  # Duplicate final ID does not inflate completion.

conflicting_duplicate = actual_format + "NPC_SAY: Cind [Hungry Bandit]|2529907200: I refuse. [TALKTARGET:id] [UTTERANCEID:utt-a]\n"
_, conflict = driver.final_speech_records(conflicting_duplicate)
assert conflict  # Same final ID with different text is evidence failure, never a positive.

final_targets = driver.target_speech("\n".join(records), "Cind [Hungry Bandit]", 2529907200)
assert len(final_targets) == 2
assert driver.extract_offer(["NPC_SAY: Cind [Hungry Bandit]|2529907200: I can guide you to The Hub. [UTTERANCEID:utt-a]"])[0]
assert not driver.extract_offer(["NPC_SAY: Cind [Hungry Bandit]|2529907200: I could guide you to The Hub. [UTTERANCEID:utt-a]"])[0]
assert driver.explicit_refusal(["NPC_SAY: Cind [Hungry Bandit]|2529907200: I won't guide you to The Hub. [UTTERANCEID:utt-a]"])

assert "Are you offering to guide me there? Please wait for my acceptance before starting." in (
    f"I meant you would lead me to The Hub and I would follow you. Are you offering to guide me there? Please wait for my acceptance before starting."
)
assert "I explicitly accept your offer to lead me to The Hub. Please start that exact trip now." == (
    "I explicitly accept your offer to lead me to The Hub. Please start that exact trip now."
)
print("RESULT ROLE-CLARIFICATION-SELFTEST PASS cases=7 actual-format=2-provisional+2-final unique-final-id-count=2")
