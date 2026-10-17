**Summary**
Tengu's first reply took about 101 s from send to speech: about 13 s server-side generation plus about 88 s in which the finished line sat in the plugin's queue because the game was paused. The 88 s is the larger part and is not an LLM problem. Nothing in Stobe pauses the game, so I can't tell from the logs why it was paused.

**Root cause**
Two delays stack:
1. Server (about 13 s): the server sends the line only after the full LLM reply is done and Pocket-TTS has synthesised the audio.
2. Plugin (about 88 s): the line arrived at 19:50:02 and was queued as ACT_SAY. The action queue is gated on `thisptr->isPaused()`, so nothing is spoken or shown until the game unpauses.

**Evidence**
Plugin times are local. Server log is UTC (19:49:49 local = 01:49:49 on 10-15).
- stobe.log 19:49:49.288: `CHAT: dispatched inputtext event`.
- stobeserver.log request req_6ad0313d4e3da: pre-LLM 1249 ms (system_prompt_and_scene 809 ms); llm first text `llm_ttft_ms` 1060 (request_elapsed 2351); `llm complete` 01:50:00 with `llm_total_ms` 10016 (`llm_after_first_text_ms` 8956); `tts_synthesis_ms` 1451; `Request completed duration_ms` 12840.
- stobe.log 19:50:02.147 `CHAT_TIMING: STREAM_LINE actor=Tengu`; 19:50:02.150 first `ACTION_QUEUE: paused; deferring queued actions size=1`. That line repeats every 1.5 s (about 55 times) until 19:51:29.202.
- First speech at 19:51:30.064: `ACTION_EXEC: SAY [Tengu]`, then `TTS_PLAYBACK: playing`.
- `gamets` is 124104 at 19:49:59.103 and still 124104 at 19:51:19.120, so game time was frozen about 80 s (paused).
- Gating code: components/STOBE/src/Functions.cpp lines 7112-7117 (`gamePaused = thisptr->isPaused()`) and lines 7163-7172 (log "paused; deferring" then return before the queue runs).

**What I ruled out**
- Network or HTTP failure: the server returned 200. The NETWORK_ERROR 12002 at 19:49:28 predates the chat and is unrelated.
- Database or memory recall: recall took 36 ms, event history 5 ms.
- Slow TTS: 1.45 s.
- Slow LLM start: about 1 s to first text.
- Plugin code pausing the game: grep for setPaused / pauseGame / ->pause( in components/STOBE/src finds nothing.

**Proposed fix**
Two independent changes.
1. Plugin, Functions.cpp around line 7163 (the bigger win). For an NPC SAY that was triggered by the player's own chat, let it run while paused, or at least show the subtitle bubble. Today the whole queue stalls on `gamePaused`. Change the early return to something like `if (gamePaused && !(nextAction.type == SAY_TYPE && isPlayerInitiatedReply)) { ...return; }`. I found no existing player-initiated flag, so you would add one to `QueuedAction` or reuse the generation or utterance id. Caveat: bubble and TTS timing is computed in game time (`speechDelayRemainingScaledMs` in the same function). While paused it already uses multiplier 1.0, but check that the TTS-hold logic does not depend on world ticks. If the pause was accidental and the current behaviour is intended, a minimum change is an on-screen "paused, reply will play on resume" hint.
2. Server, to cut the 13 s. Deliver the subtitle as soon as the LLM finishes instead of after TTS (TTS is only about 1.5 s here). Bigger win: stream the line to the client as the LLM produces it, which would cut perceived latency from about 12.8 s to about 3 s. I did not read stream.php, so check where the STREAM_LINE payload is emitted relative to the TTS call. Smaller wins: cap chat `max_tokens`, because 8956 ms after first text for a 113-character reply is slow for DeepSeek Flash and suggests a long hidden or JSON-schema reply; and cache the 27 KB system prompt to save about 0.8 s.

**How to confirm the fix worked**
- Reload the save, talk to Tengu, send one line.
- In stobe.log the gap between `STREAM_LINE` and `ACTION_EXEC: SAY` should be under about 2 s with no `ACTION_QUEUE: paused` lines (or only a few if you paused on purpose).
- In stobeserver.log the chat request's `Request completed duration_ms` should drop, and after the streaming change the first subtitle should appear in about 3 s.
- Test once unpaused and once deliberately paused to exercise both branches.

**What is not settled**
- Why the game was paused: `gamets` froze from about 19:50:00 to about 19:51:30. It could be a manual pause, a Kenshi auto-pause, or an intro state. If it was you, the plugin behaviour is arguably by design.
- Whether a 10 s LLM completion is normal here: I did not read output_from_llm.log.
- The exact delivery code in stream.php: I did not read it, so the "line sent only after TTS" point is inferred from the log ordering (STREAM_LINE at 19:50:02, right after TTS finished at 01:50:02 server time).
