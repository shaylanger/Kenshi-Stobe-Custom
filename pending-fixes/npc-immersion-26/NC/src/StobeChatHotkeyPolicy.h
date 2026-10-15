#pragma once

// Small, platform-independent decisions for the chat open/close shortcut.
// Kept separate from MyGUI callbacks so the close and typing rules have
// focused regression coverage.
namespace StobeChatHotkeyPolicy {

inline bool ShortcutAllowed(bool windowFocused, bool modifiersDown) {
  return windowFocused && !modifiersDown;
}

inline bool ShouldOpen(bool chatOpen, bool freshPress, bool shortcutAllowed) {
  return !chatOpen && freshPress && shortcutAllowed;
}

inline bool ShouldRequestClose(bool chatOpen, bool freshPress,
                               bool shortcutAllowed, bool toggleArmed,
                               bool messageInputFocused) {
  return chatOpen && freshPress && shortcutAllowed && toggleArmed &&
         messageInputFocused;
}

inline bool IsCompositionEdit(bool printableCharacter, bool backspace,
                              bool deleteKey, bool clipboardOrUndoEdit,
                              bool shiftInsert) {
  return printableCharacter || backspace || deleteKey || clipboardOrUndoEdit ||
         shiftInsert;
}

inline void DisarmAfterComposition(bool *toggleArmed) {
  if (toggleArmed) *toggleArmed = false;
}

inline bool CanConsumeCloseKey(bool toggleArmed, bool messageInputFocused,
                               bool configuredKey, bool modifiersDown) {
  return toggleArmed && messageInputFocused && configuredKey &&
         !modifiersDown;
}

inline bool OnMessageKeyDown(bool toggleArmed, bool messageInputFocused,
                             bool configuredKey, bool modifiersDown,
                             bool openingKeyHeld, bool *keyWasDown,
                             bool *closePending, bool *suppressKeyText) {
  if (!CanConsumeCloseKey(toggleArmed, messageInputFocused, configuredKey,
                           modifiersDown))
    return false;
  if (keyWasDown && !*keyWasDown && !openingKeyHeld && closePending)
    *closePending = true;
  if (keyWasDown) *keyWasDown = true;
  if (suppressKeyText) *suppressKeyText = true;
  return true;
}

inline bool ShouldCloseAfterPoll(bool closePending, bool toggleArmed,
                                 bool windowFocused) {
  return closePending && toggleArmed && windowFocused;
}

} // namespace StobeChatHotkeyPolicy
