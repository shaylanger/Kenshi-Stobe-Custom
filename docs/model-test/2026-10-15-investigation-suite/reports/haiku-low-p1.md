Report: BENCH-haiku-low-p1 (read-only investigation of slow first Tengu reply)

Summary
The slow first reply is mostly the LLM generating a long structured JSON reply, not a stall in Stobe. In the fresh-start session the first Tengu reply took 12.8 s server-side (request req_6ad0313d4e3da). About 10 s of that is the LLM call, and the text is not shown until the whole JSON finishes. The reply schema makes every chat turn produce about 250 completion tokens, most of them fields a chat line does not need (travel, region plan, preference updates, follow-up update). Proposed fix: shrink what a chat reply asks the model for and send the message as soon as it streams. Not yet applied; nothing was changed.

Root cause
Chat replies request a full structured JSON object on every turn, with about 250 completion tokens for a roughly 110-character line. At DeepSeek V4.1 Flash speed that is about 8 to 9 s of generation after the first token. The server does not start TTS or send the line to the game until the stream is complete (chunks_emitted 0, actions_streamed false), so the player waits for the whole object.

Evidence (server log /var/www/html/StobeServer/log/stobeserver.log, times 2026-10-15 UTC)
- 01:49:49.321 chat request ingress, req_6ad0313d4e3da (Shay: "What's up, Tango?", target Tengu).
- 01:49:50.569 Latency stage pre-llm complete, pre_llm_ms 1249 (system_prompt_and_scene 809 ms, the rest is small).
- 01:49:50 LLM stream dispatch, model deepseek-ai/DeepSeek-V4.1-Flash, max_tokens 1950, response_format json_schema.
- 01:49:51.672 llm first text, llm_ttft_ms 1060.
- 01:50:00.628 llm complete, llm_total_ms 10016, llm_after_first_text_ms 8956.
- 01:50:00.683 TTS start; 01:50:02 TTS audio synthesized, tts_synthesis_ms 247 (duration 8.7 s of audio).
- 01:50:02 Request completed, status 200, duration_ms 12840.
- Same pattern on the next Tengu turn, req_6ad031b0f0dea: 01:51:45.576 pre-llm complete (590 ms), first text 1431 ms, llm_total_ms 9194, after-first-text 8379 ms.
- /var/www/html/StobeServer/log/output_from_llm.log block at 2026-10-15T01:50:00 (req_6ad0313d4e3da): prompt_tokens 12321, cached_tokens 0, completion_tokens 257, finish_reason stop. The response_text includes character, listener, message, mood, action, target, destination, item, lang, amount, max_cats, travel_decision, travel_kind, travel_leader, travel_destination, travel_player_quote, travel_reason, region_plan_decision, proposed_region, preference_updates, followup_update and more.
- The second turn logged prompt_tokens 12353, cached_tokens 0, completion_tokens 244.
- connector/openaijson.php ~L1332 (first text log), ~L1579 (complete log, stream chunks), L394 stobeExtractDeltaContent (reads only delta content).
- lib/social_followups.php L73-77: followup_update is added to the schema and marked required on every reply; L171 prompt text describes it.
- Database (SELECT only): general_settings has no CHAT_REASONING_MAX_TOKENS row, so the code default of 300 applies. Reasoning is not the bottleneck: the usage shows reasoning_tokens 0.

What you ruled out
- Pre-LLM work: about 1.2 s on a cold start, 0.6 s on the next turn. Memory recall is 25 to 36 ms (no hits). Not the bottleneck.
- TTS: about 0.25 s synthesis. Fine.
- Relationship eval: it runs after the reply is sent (01:49:50 log lines are after the reply), so it does not delay the first response.
- Hidden reasoning: reasoning_tokens is 0 in the usage block; the cost is in the visible JSON.
- Cache miss as the main cause: cached_tokens is 0 on both replies, which adds to time-to-first-token (about 1 s), but it does not explain the 9 s stream.
- Shared Stobe/WSL load: not measured in this run.

Proposed fix (not applied; for you to apply later)
1. Shorten the chat reply schema (biggest win, expected to cut roughly 250 to 60-90 completion tokens, so about 2 to 3 s instead of 9 s). For chat/rechat turns, request only character, listener, message, mood, action, target, item, amount. Move travel_*, region_plan_*, preference_updates and followup_update to the background calls that already exist, or request them only when the turn actually needs them. Files: lib/social_followups.php (the schema block at L73-77 should be added only for non-chat events), and the chat schema builder that the chat processor uses (find where region_plan_decision and travel_decision are added to the schema for chat; the chat processor is processor/chat.php and the response_schema stage is in the pre-llm code path).
2. Send the message early: in connector/openaijson.php, while the stream is open, parse the "message" string from the partial JSON and pass it to the TTS and reply path at once (then send the rest of the fields when the stream ends). This makes the first visible line come about 1 s after dispatch instead of after the whole object.
3. Cache: keep the system prompt prefix stable across turns (the stobeApplyPromptCacheKey function already sets prompt_cache_key per NPC). cached_tokens is 0 on consecutive turns, so check what changes at the start of the prompt each turn (the time, location or nearby list placed before the stable part). Saves about 1 s of TTFT.

How to confirm the fix worked
- Run the same test: fresh launch, first chat line to Tengu. In stobeserver.log, grep for "Latency stage llm complete" and "Request completed" with the same request_id. Target: llm_after_first_text_ms under 3000 and duration_ms under about 5000 on the first turn.
- Check output_from_llm.log: completion_tokens under about 100 for chat turns, and the JSON still parses (structured_json true in "LLM stream response generated").
- Check the chat still gets its travel/region/followup behaviour through the background calls (the relationship and travel logs still show their decisions).
- Offline: the server regression tests should still pass (stobe-tests), and a check that the chat schema has no followup_update/travel fields.

What is not settled
- How much of the 9 s is DeepInfra throughput versus output length. The 244 to 257 completion tokens at about 27 tokens/s explain it, but I did not measure provider speed directly.
- Whether the player-visible delay also includes the game side (the client waits for the reply event). The server side is 12.8 s; the game-side delay was not measured.
- Why cached_tokens is 0: the prompt_cache_key is set, but the prefix may vary per call. Not traced.
- Reading note: one early grep ran over the Windows repo and returned a few lines from pending-fixes\ (usleep call lines only). I did not open or use any pending-fixes content; the rest of the investigation used only the live WSL tree, logs and SELECT queries.
