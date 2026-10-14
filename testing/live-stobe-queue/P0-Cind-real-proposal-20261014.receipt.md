# Real Cind proposal baseline

RESULT P0-TRAVEL-START-MOVE-4080-001 FAIL evidence: completed target response was ambiguous or lacked a narrow affirmative offer; no acceptance sent.

Actual reviewed packet: R6 body0EAEA48994D1FEBD6ABB5D8687A09F122AB214EE1DE1F8225C8A807D8DCABB7D; driverEB0BA4C4F3B3F7091D1A8ED79E7CCD356823B23850B6B6885172C6B366213C70. Execution80024 terminated. Owned output: C:\KenshiTestRuns\stobe-validation\4080-p0-current-driver-20261014-20261014-114029-951\run.

Real backend request req_6acfcca75db97, chat/statusok at18:41:48UTC. Native send18:40:39.305UTC, finalSAY18:41:48.887, responsecomplete18:41:49.581. Approximately69.6seconds send→finalSAY; TTFT/prefill and provider token counts unavailable from this audit (reported0 must not be treated as actualzero). Slot0 idle at18:42:35UTC, n_prompt_tokens11189 observed after completion.

Exact actor Cind [Hungry Bandit] #2529907200/2, playerShay, copiedsave kah-stobe-4080-standalone-active SHA d339e3052345460f6e500d80f72168608747624250929727f97e1d09aa5cd6d0. Fresh world was unpaused/advancing; Cind conscious/no orders/NULL_TASK,18.6m; destinationTheHub catalogrow1/378, XYZ[-50978.8,1533.1,2932.5]. Loaded nativeStobeAEF84C…1907C, Harness974DB…3025D; private18084 and EAC727 legacy switching source. This is baseline coverage, not current557 release coverage. Supported legacy session checks passed; actual native header use remains unproven, and no PASS is asserted.

The completed reply did not give a clear NPC-leading commitment; it mixed player-leading wording with NPC route knowledge. Two nativeACTION_EXEC markers were SAY only. Responsecomplete marker declared2chat/0action lines. No acceptance or travelstart was sent. Raw target reply stays in owned output; no prompt/model transcript is duplicated here.

Real stream-format finding:4NPC_SAY records comprise2short provisional texts withoutUTTERANCEID plus2final tagged texts. Existing speech counter counts all4; queue owner must add actual-format regression and final utterance counting/deduplication before treating that count as complete target-response proof.

Next: reviewed leader-role clarification case, then conditional acceptance and exact nativeendpoint movement proof; preserve this outcome. Post-chat mechanical query D3FF5…ECFC1 returned queryOK/affinity0(runtime_default)/candidates[], so native context-sync procedure/source membership is still required for mechanical fixtures. Temporary summary720 is active; exact rollback timestamp and receipt are in4080-summary-defer-applied-20261014.receipt.md.
