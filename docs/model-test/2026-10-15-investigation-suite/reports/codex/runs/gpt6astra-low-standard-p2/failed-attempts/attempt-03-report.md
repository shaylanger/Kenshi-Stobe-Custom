## Summary

**BENCH-R001 — read-only investigation; no changes made.**

I could not establish either root cause from the frozen evidence because the permitted tools stopped responding. Below is a provisional explanation and proposed fix, **not a verified diagnosis or an applicable code patch**.

Your report suggests two separate failures:

- Tengu’s identity was confused with the famous Emperor Tengu.
- Your identity correction produced an unrelated statement about accepting a job.

The second statement alone does **not** establish that the system actually started a job.

## Root cause

**Identity confusion — unconfirmed hypothesis:** character selection, biography lookup, or prompt construction may associate NPCs by display name. Alternatively, the correct character context may have reached the model, but the model substituted its knowledge of Emperor Tengu.

These require different fixes: incorrect identity lookup needs code changes; correct context ignored by the model needs stronger identity grounding.

**Job response — unconfirmed hypothesis:** the reply may have been influenced by unrelated conversation history, job-related instructions, or mistaken intent classification. It could also have been invented dialogue without any job-state change.

I could not inspect the relevant exchange, prompt, or task records to distinguish these possibilities.

## Evidence

Successfully inspected:

- `README.txt:8–22`: the frozen server is the recorded snapshot; its tree reportedly matched the server at test start.
- `README.txt:24–33`: native source was reconstructed from backups and was **not** rebuilt and byte-compared with the DLL.
- `README.txt:38–45`: the original game `stobe.log` is absent, and some supplied game files postdate the test.
- A complete search of `logs/chat_llm_full_capture.log`—10,620,958 bytes—returned no matches for `Tengu`. This establishes absence only from that file, not from other logs.

Evidence collection then failed:

- Tengu search in `logs/output_from_llm.log`: timeout.
- Emperor Tengu search in `server/lib`: timeout.
- Directory listing of `server/lib`: timeout.
- Database table discovery through `information_schema.tables`: timeout.
- Direct bounded read of `server/chat.php`: timeout.

No relevant database values, dialogue timestamps, or implementation lines were obtained.

## What you ruled out

- The available full-capture log does not contain the literal name `Tengu`.
- Nothing retrieved proves that a job was actually created or accepted.

I could **not** rule out a name collision, contaminated biography, mixed conversation history, prompt interference, intent-classification error, or model hallucination.

## Proposed fix

The following is an implementation design to apply **after locating and verifying the responsible code**. I cannot responsibly name functions or provide a source diff without reading them.

**1. Ground the speaker in the actual game actor.**

At the actor-resolution and biography-selection boundaries:

- Use the game’s stable actor identifier, scoped to the playthrough, to select the speaker and their history.
- Do not attach a famous NPC’s biography solely because the display names match.
- Require a verified canonical/template identity before assigning Emperor Tengu’s biography.
- Make authoritative actor facts explicit in the prompt: actor identifier, name, faction, gender, and known role. Unknown facts should remain unknown.

For this NPC, once confirmed by game data, the prompt should establish that she is the Anti-Slaver named Tengu and that sharing a name does not make her Emperor Tengu.

Conceptually:

```text
speaker = resolve(playthrough_id, actor_id)
biography = lookup_verified_canonical_identity(speaker)

if no verified canonical identity:
    use this actor's own profile and observed facts
```

**2. Separate identity corrections from job intent.**

At the dialogue-intent and task-dispatch boundaries:

- Treat “you are not Emperor Tengu” as an identity correction.
- Do not infer an offer, acceptance, cancellation, or active job from that sentence.
- Require explicit task intent and the existing validation rules before changing task state.
- If no job exists or is being discussed, avoid injecting irrelevant job-acceptance instructions into the reply context.

The desired response would acknowledge the mistaken identity without introducing a job.

**3. Repair persistent contamination only if confirmed.**

If inspection finds Emperor-specific biography or unrelated job memories stored against this actor, correct those particular records. A prompt-only fix would leave contaminated memories available for later replies. Do not delete all history or rename every NPC called Tengu.

## How to confirm the fix worked

In a separate writable test environment:

1. Start a fresh conversation with the Anti-Slaver Tengu. Verify the resolved actor ID and supplied profile belong to her.
2. Ask who she is. Confirm she does not claim the Emperor’s identity or status.
3. Say, “You are not Emperor Tengu.” Confirm she acknowledges the correction without mentioning an unsolicited job.
4. Compare task state before and after that message. Confirm no task is created, accepted, or cancelled.
5. Test Emperor Tengu and another same-name NPC separately. Confirm biographies and conversation histories remain distinct.
6. Make a genuine job request afterward. Confirm legitimate job handling still works.

Inspect both the raw model reply and the final delivered reply to determine where any unwanted wording originates.

## What is not settled

The actual prompts and replies, actor identifiers, stored biographies, conversation history, task state, and responsible files/functions remain unverified. Consequently, there is no evidence-backed exact patch yet.

Completing this investigation requires restoring access to the **same frozen tools and snapshot**. No live-system access or code changes are needed to establish the cause.