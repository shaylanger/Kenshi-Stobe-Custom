# Bounded 4080 preflight: live capture succeeded, formatter failed

V3 wrapper `61C13193AEDD702EFD9B0A50BD01E7D3155F1785D397B174474D8CF4D7D2D7F9` and exact corrected body `DEBE1258C549EB4598EEDD5D01647F3912C710B386023BF4F9499538519132F8` (copied under the stream-contract filename) executed after independent CLEAR. Caller exit1 in5.258seconds. Remote marker receiver_pid244/bash_pid14844. No timeout occurred; no game/server restart or chat happened.

The complete stage transcript was captured: route, host/instance, exact PID3452/i3 process and module metadata, on-disk AEF/Harness hashes, config127.0.0.1:18084, schema/health true at timestamp1791996726, strict private listener/root, session ready/newload4/generation manager match, world copied save/unpaused, game_hours87.9082(day3/15:54), input isolation on, FP state, fresh Cind/Shay roster, final complete marker. Compared with earlier77.5782 hours, game time advanced.

Wrapper's final formatter nevertheless emitted `RESULT KAH-CHAT-007 FAIL setup: captured read output is incomplete; missing=evidence:PID,evidence:process path,evidence:Stobe on-disk hash,evidence:Harness on-disk hash,evidence:private backend host,evidence:private backend port,evidence:actor roster result,evidence:speaker; stderr_captured=false stderr_class=empty stderr_lines=0`.

These fields are visibly present in the captured transcript. This is a transport evidence-formatting bug, not evidence the game/session lacks those facts. Reconstructed CRLF breaks existing anchored completeness regexes. Additionally, per-line PowerShell event capture reordered some stdout lines (module path part2 before part1; config host/port grouping), so this new wrapper must not replace the canonical transport until per-stream ordering and completeness checks are fixed and regressions pass. The earlier native actor resolver PASS used the prior progress-only wrapper and is unaffected.

Owner `4080_progress_format_helper` is repairing ordered capture and normalization in a new immutable candidate. Existing V3 remains preserved. P0 travel row may use the proven prior transport after its separate exact driver review; this tooling fix must not block the row.
