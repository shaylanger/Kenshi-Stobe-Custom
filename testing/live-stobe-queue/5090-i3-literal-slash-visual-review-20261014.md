# 5090 i3 literal-slash visual review — 2026-10-14

**Verdict: PASS for the requested screenshot-visible assertions.** This is a visual review only; it does not establish the full gameplay or integration goal.

Inspected the four source screenshots at `D:\KenshiInst\3\mods\AutomationHarness\shots\`:

- `kah-int-001-5090-i3-20261014-01-open.png`: CHAT BOX is visibly open with an empty input.
- `kah-int-001-5090-i3-20261014-02-close.png`: CHAT BOX is visibly closed. Together, 01 then 02 visually match open on the first slash and close on the untouched second slash.
- `kah-int-001-5090-i3-20261014-03-caret.png`: CHAT BOX remains open. The input is empty and a text caret is visible at its left edge after the reported native click at (500,323).
- `kah-int-001-5090-i3-20261014-04-literal.png`: CHAT BOX remains open and the input visibly contains `a/`; the caret is immediately after the slash.

The operator reports the native UI tree had 18 widgets and `StobeChatInput` value `a/`, and that the draft was discarded via `stobe_npcinfochatclose` without sending. These are supplied run facts, not claims independently established by the screenshots. Isolation/focus/display metadata is likewise supplied by the operator.
