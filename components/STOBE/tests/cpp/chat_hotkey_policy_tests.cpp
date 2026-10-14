#include "StobeChatHotkeyPolicy.h"

#include <cstdio>
#include <stdexcept>
#include <string>

using namespace StobeChatHotkeyPolicy;

static int g_checks = 0;
static void check(bool ok, const std::string &what) {
  ++g_checks;
  if (!ok) throw std::runtime_error(what);
}

int main() {
  try {
    check(ShouldOpen(false, true, ShortcutAllowed(true, false)),
          "fresh unmodified press opens focused chat");
    check(!ShouldOpen(false, false, true), "held key does not repeat open");
    check(!ShouldOpen(false, true, ShortcutAllowed(false, false)),
          "unfocused game ignores shortcut");
    check(!ShouldOpen(false, true, ShortcutAllowed(true, true)),
          "modified key remains ordinary input");

    check(ShouldRequestClose(true, true, true, true, true),
          "fresh second press closes an untouched focused draft");
    check(!ShouldRequestClose(true, false, true, true, true),
          "held key does not repeat close");
    bool toggleArmed = true;
    DisarmAfterComposition(&toggleArmed);
    check(!toggleArmed &&
              !ShouldRequestClose(true, true, true, toggleArmed, true),
          "composition permanently disarms close shortcut");
    check(!ShouldRequestClose(true, true, true, true, false),
          "shortcut does not close when textbox lacks focus");
    check(!ShouldRequestClose(true, true, false, true, true),
          "modified shortcut does not close");

    check(IsCompositionEdit(true, false, false, false, false),
          "typed character counts as composition");
    check(IsCompositionEdit(false, true, false, false, false),
          "backspace counts even if draft becomes empty");
    check(IsCompositionEdit(false, false, true, false, false),
          "delete counts as composition");
    check(IsCompositionEdit(false, false, false, true, false),
          "cut paste and undo count as composition");
    check(IsCompositionEdit(false, false, false, false, true),
          "shift insert counts as composition");
    check(!IsCompositionEdit(false, false, false, false, false),
          "focus movement alone does not count as composition");

    check(CanConsumeCloseKey(true, true, true, false),
          "close key is consumed only for untouched focused draft");
    check(!CanConsumeCloseKey(false, true, true, false),
          "typed slash remains ordinary input after composition");
    check(!CanConsumeCloseKey(true, false, true, false),
          "slash is not consumed outside message input");
    check(!CanConsumeCloseKey(true, true, true, true),
          "modified slash is retained as ordinary input");
    check(!CanConsumeCloseKey(true, true, false, false),
          "other keys are not consumed");

    bool keyWasDown = false;
    bool closePending = false;
    bool suppressKeyText = false;
    check(OnMessageKeyDown(true, true, true, false, false, &keyWasDown,
                           &closePending, &suppressKeyText),
          "draft key callback recognizes the close press");
    check(keyWasDown && closePending && suppressKeyText,
          "callback arms deferred close and suppresses emitted slash");
    check(ShouldCloseAfterPoll(closePending, true, true),
          "poll closes after callback ordering");
    check(!ShouldCloseAfterPoll(closePending, true, false),
          "deferred close waits until game window is focused");

    closePending = ShouldRequestClose(true, true, true, true, true);
    check(ShouldCloseAfterPoll(closePending, true, true),
          "poll-first ordering requests close on the fresh physical edge");

    keyWasDown = false;
    closePending = false;
    suppressKeyText = false;
    check(OnMessageKeyDown(true, true, true, false, true, &keyWasDown,
                           &closePending, &suppressKeyText),
          "opening-key callback is still recognized");
    check(!closePending && suppressKeyText,
          "opening press is consumed without closing the new chat");
  } catch (const std::exception &e) {
    std::printf("FAIL chat_hotkey_policy_tests: %s (after %d checks)\n",
                e.what(), g_checks);
    return 1;
  }
  std::printf("PASS chat_hotkey_policy_tests (%d checks)\n", g_checks);
  return 0;
}
