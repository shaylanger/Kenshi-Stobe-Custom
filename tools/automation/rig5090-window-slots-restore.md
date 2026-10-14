# 5090b/5090c window placement restore plan

This applies only to the two existing, privately installed windows: instance 2 at
`D:\KenshiInst\2\kenshi_x64.exe` (5090b) and instance 3 at
`D:\KenshiInst\3\kenshi_x64.exe` (5090c). The helper creates no windows and
does not launch, stop, focus, or send input to Kenshi.

Before moving either window, the helper captures its PID, HWND, exact executable
path, title, and original outer `GetWindowRect` bounds. It writes both entries
atomically to `C:\KenshiTestRuns\rig5090-window-slots.restore.json` before the
first move. If that receipt already exists, another placement fails closed.
The two original rectangles are kept separately as `Instance2.Original` and
`Instance3.Original`; their corresponding approved placements are stored as
`Target` in the same entries.

After the test window layout is no longer needed, the sole rig operator restores
both windows with the same pinned PIDs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\KenshiModding\tools\automation\rig5090-window-slots.ps1 -Restore -Instance2Pid <i2-pid> -Instance3Pid <i3-pid>
```

Restore rechecks both executable paths, HWND-to-PID association, exact instance
title markers, and receipt identities. It accepts each current rectangle only
when it still equals either that window's recorded original or target rectangle;
otherwise it refuses to overwrite an intervening user move. It restores each
original rectangle using `SWP_NOACTIVATE | SWP_NOZORDER`, verifies exact outer
bounds, then removes the receipt. A partial failure attempts to return attempted
windows to the rectangle they had immediately before restore and keeps the
receipt for recovery.

The helper was only run with `-SelfTest` during implementation. No host windows
were moved, and no restore receipt was created.
