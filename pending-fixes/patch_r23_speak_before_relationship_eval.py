#!/usr/bin/env python3
"""Money sentence delay (~6 s): a held-back line waited for the relationship evaluation.

chat.php ran stobeEvaluateRelationshipsForTurn() -- a synchronous LLM call (relationship
connector, OpenRouter) -- before speaking any reply that wasn't streamed yet. Held-back
money sentences (and every other non-streamed reply) waited for it.

The evaluation only needs the reply text; the spoken text is the reply minus relationship
tags (what the evaluation returned as clean_response). Now: strip the tags, speak, then
evaluate. Streamed replies keep the old order (already spoken).

Usage: patch_r23_speak_before_relationship_eval.py <StobeServer tree root>  (idempotent)
"""
import sys
from pathlib import Path

chat = Path(sys.argv[1]) / 'processor' / 'chat.php'
c = chat.read_text(encoding='utf-8')
if 'speak before the relationship evaluation' in c:
    print('already patched'); sys.exit(0)
old1 = """    $relationshipEval = stobeEvaluateRelationshipsForTurn(
        $targetNpc,
        $replyTarget,
        $relationshipInput,
        $responseText,
        $npcData,
        'chat'
    );
    $responseText = sanitizeForKenshi(trim(strval($relationshipEval['clean_response'] ?? $responseText)));"""
new1 = """    if (!$alreadyStreamed) {
        // Not spoken yet: speak before the relationship evaluation (an LLM call), run it after.
        $deferredRelationshipEval = [$relationshipInput, $responseText];
        $responseText = sanitizeForKenshi(trim(stobeStripRelationshipCommandTags($responseText)));
    } else {
        $relationshipEval = stobeEvaluateRelationshipsForTurn(
            $targetNpc,
            $replyTarget,
            $relationshipInput,
            $responseText,
            $npcData,
            'chat'
        );
        $responseText = sanitizeForKenshi(trim(strval($relationshipEval['clean_response'] ?? $responseText)));
    }"""
old2 = """    stobeStreamDialogueResponse(
        $targetNpc,
        $npcData,
        $textToSpeak,
        $responseActions,
        'chat',
        $replyTarget,
        intval($gamets)
    );
}"""
new2 = """    stobeStreamDialogueResponse(
        $targetNpc,
        $npcData,
        $textToSpeak,
        $responseActions,
        'chat',
        $replyTarget,
        intval($gamets)
    );
}
if (isset($deferredRelationshipEval)) {
    try {
        stobeEvaluateRelationshipsForTurn($targetNpc, $replyTarget, $deferredRelationshipEval[0], $deferredRelationshipEval[1], $npcData, 'chat');
    } catch (Throwable $relationshipEvalError) {
        stobeLogWarn('Relationship evaluation after speaking failed', ['npc'=>$targetNpc, 'error'=>$relationshipEvalError->getMessage()]);
    }
}"""
for o, n in [(old1, new1), (old2, new2)]:
    assert c.count(o) == 1, 'anchor: ' + o[:60]
    c = c.replace(o, n)
chat.write_text(c, encoding='utf-8', newline='')
print('patched', chat)
