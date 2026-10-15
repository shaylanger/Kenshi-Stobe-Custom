#!/usr/bin/env python3
"""Source-bound checks and a small mock for Activity chat actor registration."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
src = ROOT / "src"
chat = (src / "ChatBox.cpp").read_text(encoding="utf-8")
compat = (src / "KenshiAiCompat.cpp").read_text(encoding="utf-8")
header = (src / "KenshiAiCompat.h").read_text(encoding="utf-8")


def check(condition: bool, description: str) -> None:
    if not condition:
        raise AssertionError(description)
    print(f"PASS {description}")


def function_body(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for pos in range(opening, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1 : pos]
    raise AssertionError(f"unterminated function: {signature}")


# Bind this regression to the production API, guard, call order, and reset path.
register = function_body(
    compat,
    "bool RegisterCharacterHandle(Character *character, unsigned int expectedSerial)",
)
send_region = chat[chat.index("const unsigned activityActor = static_cast<unsigned>(strtoul(") :]
send_region = send_region[: send_region.index("streamTask->npcName =")]
resolve_impl = function_body(
    compat,
    "Character *ResolveCharacterImpl(GameWorld *world, unsigned int serial,",
)
clear_cache = function_body(compat, "void ClearCharacterHandleCache()")

check(
    "RegisterCharacterHandle(Character *character, unsigned int expectedSerial)" in header,
    "exact registration API is declared",
)
check(
    "runtimeHandle.serial != expectedSerial" in register
    and "runtimeHandle.isNull()" in register
    and "runtimeHandle.isValid()" in register
    and "g_characterHandles[expectedSerial] = runtimeHandle" in register,
    "registration rejects wrong, null, and invalid live handles before caching",
)
check(
    send_region.index("RegisterCharacterHandle(targetNpc, activityActor)")
    < send_region.index("CaptureActivityChatTurn(")
    and "RegisterCharacterHandle(player, activityRequester)" in send_region,
    "chat registers exact target and player before capturing the Activity turn",
)
check(
    "g_characterHandles.find(serial)" in resolve_impl
    and "HandlesMatch(found->second, liveHandle)" in resolve_impl
    and "g_characterHandles.erase(serial)" in resolve_impl,
    "resolver retains exact cached-handle validation and stale-entry removal",
)
check(
    "g_characterHandles.clear()" in clear_cache,
    "world reset still clears the identity cache",
)


# Native API objects cannot be constructed outside Kenshi, so exercise the same
# serial/incarnation/cache contract with a tiny mock and keep the source checks
# above tied to the production implementation.
class Actor:
    def __init__(self, serial: int, incarnation: int = 1, valid: bool = True):
        self.serial = serial
        self.incarnation = incarnation
        self.valid = valid


def register_mock(cache: dict[int, tuple[int, int]], actor: Actor, expected: int) -> bool:
    if not expected or not actor.valid or actor.serial != expected:
        return False
    cache[expected] = (actor.serial, actor.incarnation)
    return True


def resolve_mock(cache: dict[int, tuple[int, int]], actor: Actor, serial: int):
    saved = cache.get(serial)
    if saved is None:
        return None
    if not actor.valid or saved != (actor.serial, actor.incarnation):
        cache.pop(serial, None)
        return None
    return actor


cache: dict[int, tuple[int, int]] = {}
ginkin = Actor(3947387648)
check(register_mock(cache, ginkin, 3947387648), "mock cold cache accepts exact target serial")
check(resolve_mock(cache, ginkin, 3947387648) is ginkin, "mock cold target resolves after registration")
check(register_mock(cache, ginkin, 3947387648), "mock warm cache accepts same live handle")
check(resolve_mock(cache, ginkin, 3947387648) is ginkin, "mock warm target resolves to same actor")

cache.clear()
check(not register_mock(cache, ginkin, 3947387649), "mock wrong serial is rejected")
check(resolve_mock(cache, ginkin, 3947387648) is None, "mock wrong serial cannot resolve by nearby/name fallback")

player = Actor(3454101504)
check(register_mock(cache, player, 3454101504), "mock player requester registers through exact serial")
check(
    resolve_mock(cache, player, 3454101504) is player
    and player.serial != ginkin.serial,
    "mock requester resolves as player and remains distinct from NPC actor",
)

check(register_mock(cache, ginkin, 3947387648), "mock stale-handle setup registers original incarnation")
replacement = Actor(3947387648, incarnation=2)
check(resolve_mock(cache, replacement, 3947387648) is None, "mock stale incarnation fails closed")
check(3947387648 not in cache, "mock stale entry is removed")

check(register_mock(cache, ginkin, 3947387648), "mock world-reset setup registers target")
cache.clear()  # mirrors ClearCharacterHandleCache at world reset
check(resolve_mock(cache, ginkin, 3947387648) is None, "mock world reset removes cached target")

print("RESULT ACTIVITY-CHAT-ACTOR-CACHE PASS checks=18")
