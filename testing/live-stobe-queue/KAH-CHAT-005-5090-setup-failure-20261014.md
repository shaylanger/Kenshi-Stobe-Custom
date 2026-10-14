# KAH-CHAT-005 transport attempt — setup failure

- **Scope:** Validator-cleared one-turn question to Heads or Tails Dealer on the isolated 5090 test world. The intended message was not confirmed as dispatched.
- **Attempted command:**

```powershell
wsl.exe -d DwemerAI4Skyrim3 -u root --cd /mnt/c/KenshiModding -- bash -lc 'export KAH_INSTANCE=1; . /mnt/c/KenshiModding/tools/automation/rig-env.sh >/dev/null; stobe-auto stobe_say "Heads or Tails Dealer" "You asked me to choose a direction. Would Sho-Battai be a destination you’d be willing to guide me to, or would you rather stay here?"'
```

- **Observed:** the tool returned empty stdout after about 2.8 seconds. The inner command's exit code and stderr were not retained by the caller, so they are unknown. No matching `TEST_INBOX` line exists in `D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\stobe.log`. The actual KAH outbox at `D:\Steam\steamapps\common\Kenshi\mods\AutomationHarness\outbox.txt` showed only the prior state query (`k1791937744210_41099_1`) after the previous chat receipt; there is no receipt/request ID for this attempted utterance.
- **Classification:** `FAIL setup/transport`, not a product result. Do not treat the row as dispatched and do not retry unchanged. The queue supervisor assigned the quoting/transport root-cause diagnosis; wait for a corrected transport and fresh preflight before sending once.
- **World state at last fresh preflight:** PID 86884, isolated save `kah-5090-legacy-auth-20261013-1740`, world unpaused at speed 1.0, input isolation ON/focused=0/DISPLAY2. Beak `#3172973568` was the speaker; Heads or Tails Dealer `#2336669952/1` was alive with no orders/player orders. No pending travel agreement or player trip.
