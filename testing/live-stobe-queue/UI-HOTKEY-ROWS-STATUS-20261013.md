# UI hotkey row execution status — 2026-10-13

`kah-ui-001-stobe-chat-hotkey.sh` and `kah-ui-002-kenshifp-toggle-key.sh` are superseded and blocked for execution. Their action wording does not establish that clicks and keys use isolated KAH injection. Preserve both files as immutable history; do not queue or execute them.

Use only the replacement specifications below, and only after the rig operator confirms the exact candidate is installed and loaded on that isolated instance:

| Replacement row | Candidate loaded SHA-256 required | Scope |
|---|---|---|
| KAH-UI-003 (`kah-ui-003-stobe-chat-hotkey-isolated.sh`) | Stobe `EFE7B71C0B2D3A7A0F7A1F18033F88BF64F3BE6A3B055C506E913BA1D3CE61BA` | Isolated injected fresh open; textbox caret and literal `/` draft; separate fresh untouched chat closes on second `/` |
| KAH-UI-004 (`kah-ui-004-kenshifp-toggle-key-isolated.sh`) | KenshiFP `50C1698688D65E2A548C43E7C38F694BD28383FEEA36C1F269D990F2B574D270` | Isolated injected key capture, Escape cancel, INI save/reopen, Right Alt reset, rebound toggle, focus/UI guards |

Both replacements require `input_isolation on`, status proving `isolation=on` and `focused=0`, and injected mouse/key actions only (`stobe-auto mouse_inject` / `key_inject` or the documented isolated helper scripts). No physical keyboard/mouse, foreground switching, or focus helpers. Every ACK is transport-only; UI read state and screenshots prove the result. Queue both rigs where setup permits, with independent candidate install/hash receipts. No prior 5090 evidence on another DLL hash validates these candidates.
