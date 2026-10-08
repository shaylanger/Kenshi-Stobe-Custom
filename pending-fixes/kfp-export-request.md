# KenshiFP export request (STOBE items 135/136, m52)

Stobe needs the character KenshiFP controls in first person, so chat speaks as that character (136)
and the NPC panel uses it as the observer (135).

Please export from KenshiFP.dll (C linkage, no name mangling):

```c
/* The Character* KenshiFP currently controls in first person; NULL when FP mode is off. */
__declspec(dllexport) void *KenshiFP_ControlledCharacter(void);
```

Stobe already looks it up with `GetProcAddress(GetModuleHandleA("KenshiFP.dll"), "KenshiFP_ControlledCharacter")`
(ChatBox.cpp `StobeFpControlledCharacter`) and only accepts a pointer that is one of the player's squad
characters. Until the export exists Stobe falls back to "the squad member whose head the camera sits in"
(horizontal < 1.5, camera 0.4-3.0 above the feet), which can pick the wrong one when two members stand
in the same spot. Once exported, the fallback is no longer used.
