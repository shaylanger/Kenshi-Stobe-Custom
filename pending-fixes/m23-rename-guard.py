#!/usr/bin/env python3
"""m23 fixer 8: Stobe identity rename must not overwrite a name changed after the request (REL SR09/SR06).

Run m22 batch E: the harness renamed fresh spawns ("Rel Wren", "Rel Vorn"); the identity worker had already sent their
generic name "Hungry Bandit" to /get_batch_identities, and the reply's NPC_RENAME was applied ~1 s later on top of the
new name ('Rel Wren' -> 'Skenn 2 [Hungry Bandit]'), so the scenarios lost their NPC (stobe_say target not found, p2-04b
"no character named Rel Vorn"). Same race for a player renaming an NPC in the UI.
Fix: the rename message carries the name that was sent ("NPC_RENAME: <serial>|<new>|<sent>"); it is applied only if the
character still has that name, else skipped and logged (NAME_ASSIGN: kept '<current>' ...).

Usage: python3 m23-rename-guard.py <STOBE-src root>   (marker M23_RENAME_GUARD)
"""
import pathlib, sys

MARK = 'M23_RENAME_GUARD'
p = pathlib.Path(sys.argv[1]) / 'src/main.cpp'
s = p.read_text()
if MARK in s:
    print('already patched'); sys.exit(0)

pairs = [
(
'''          std::string renameMsg = "NPC_RENAME: " + sSerial + "|" + newName;''',
'''          // M23_RENAME_GUARD: carry the name that was sent, the rename applies only if it is still current
          std::string sentName;
          for (size_t bi = 0; bi < batch.size(); ++bi)
            if (batch[bi].serial == serial) { sentName = batch[bi].name; break; }
          std::string renameMsg = "NPC_RENAME: " + sSerial + "|" + newName + "|" + sentName;'''),
(
'''          std::string newName = payload.substr(sep + 1);
          if (serial > 0 && !newName.empty() && thisptr) {''',
'''          std::string newName = payload.substr(sep + 1);
          // M23_RENAME_GUARD: "<new>|<sent>": skip when the character was renamed after the request
          std::string sentName;
          bool hasSent = false;
          size_t sep2 = newName.find('|');
          if (sep2 != std::string::npos) {
            sentName = newName.substr(sep2 + 1);
            newName = newName.substr(0, sep2);
            hasSent = true;
          }
          if (serial > 0 && !newName.empty() && thisptr) {'''),
(
'''                std::string oldName = (*it)->getName();
                (*it)->setName(newName);''',
'''                std::string oldName = (*it)->getName();
                if (hasSent && !sentName.empty() && oldName != sentName) {
                  Log("NAME_ASSIGN: kept '" + oldName + "' (renamed after the identity request for '" + sentName +
                      "'; dropped '" + newName + "', serial " + ToString(serial) + ")");
                  break;
                }
                (*it)->setName(newName);'''),
]
for old, new in pairs:
    c = s.count(old)
    if c != 1:
        raise SystemExit(f'anchor found {c}x: {old[:80]!r}')
    s = s.replace(old, new, 1)
p.write_text(s)
print('patched', p)
