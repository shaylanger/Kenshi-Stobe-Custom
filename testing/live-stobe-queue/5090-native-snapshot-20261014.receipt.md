# 5090 main-i1 native snapshot

Owner `/root/operator_5090_recover`. Exact independent review and fresh Agent Validator CLEAR; executed once via `require_escalated`.

Command: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\invoke-wsl-captured.ps1 -BashBodyPath C:\KenshiModding\pending-fixes\rig5090-validation\5090-i1-kah-readiness.sh`.

Wrapper SHA256 `9E14992B65197BD1CDFF61768C3340008CE9FE389EBECC3EE51AE7F0C00156FC`; body SHA256 `A21C304F3066ADD61E1AD27E92BA6230D57D5A808BD993D14A269A65756D0B08`; packet SHA256 `0C06696C4158546356C3263B77D3ED75065D297503AAE23B135738090563DB05`.

The presence-only inbox/lock gate passed before each of three normal KAH client commands. Exit 0, no stderr. Normal KAH transport acquired/released its own lock, wrote/consumed command inbox files, and received outbox responses; no preexisting marker was cleared or taken over.

Raw native results:

```
phase=world save=kah-fresh-start-5090-copy-20261013-152239 last_saved=test-npcs-following paused=0 speed=1.0 squad=1 player=Shay
isolation=on hooks=user32:8/8,dinput:4/4 wndproc=1 devices=kbd:1,mouse:2,other:0 dropped_msgs=71 dropped_di=0 blocked_clip=0 blocked_setcursor=880938 blocked_foreground=0 hidden_deactivate=0 restored_minimized=0 injected_keys=8 injected_mouse=6 held=none cursor=4480,1080 frames=1270284 focused=0 iconic=0 window=-2560,0,1600x900 monitor=\\.\DISPLAY2
2 within 80.0: Bangs #3725097728/3 [Anti-Slavers] pos=52733.4,2484.7,61751.1 dist=48.0 race=Dra'ak | Shay #3454101504/1 [Nameless] pos=52770.2,2478.2,61781.2 dist=0.0 race=Greenlander
RESULT KAH-5090-I1-SNAPSHOT-COLLECTION PASS commands=3 route=main-instance-1 gates=presence-only-before-each meaning=successful-response-collection-only
```

`injected_keys`/`injected_mouse` are cumulative preexisting counters, not input sent in this attempt. No input command was sent. This is collection and current native setup evidence, not gameplay PASS, session authorization proof, or an active continuing row.

Next: exact-reviewed sanitized session read for the current copied campaign, then freshly cleared gameplay row with current target/state checks.
