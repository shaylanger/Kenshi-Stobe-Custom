#pragma once
// Stobe's test commands through the Kenshi Automation Harness (a separate
// RE_Kenshi test plugin, see StobeHarnessBridge.cpp). Does nothing when the
// harness isn't installed.

#include <string>
#include <vector>

class Character;
class GameWorld;

namespace Stobe {
namespace HarnessBridge {

// Runs one queued command: f[0] = request id, f[1] = command (ping, mode,
// say, state, give_cats, give_item), f[2..] = args.
typedef std::string (*RunFn)(GameWorld *world, Character *sel,
                             const std::vector<std::string> &f, bool &ok);

// Registers the commands with the harness; call from startPlugin. Drain()
// retries while the harness hasn't loaded yet (plugins load in mod-list order).
void Connect();

// Runs the queued commands and answers them; call from the player update
// hook (where the old test_inbox.txt was read).
void Drain(GameWorld *world, Character *sel, RunFn run);

} // namespace HarnessBridge
} // namespace Stobe
