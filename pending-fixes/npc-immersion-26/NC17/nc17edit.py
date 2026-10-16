# NC17 = NC16 + a player-faction (squad) companion is a legal Hunt/activity partner when the player requests it
# (rows IMM-26-a / 22-a / 26-b / 26-c).  Usage: python3 nc17edit.py <NC16-tree-root>   (root contains src/).
# Edits src/NativeTravelReceiptPolicy.h (pure ClassifyStartActor) and src/NativeTravelLifecycle.cpp (Start uses it).
import sys,io
root=sys.argv[1]
def rw(path):
    p=root+'/'+path
    return p,io.open(p,'r',encoding='utf-8',newline='').read()

# 1. pure policy
p,s=rw('src/NativeTravelReceiptPolicy.h')
anchor='} } // namespace Stobe::NativeTravelReceiptPolicy'
assert s.count(anchor)==1 and 'ClassifyStartActor' not in s
policy='''// Who may be given an owned travel/activity order by Start().
// A companion in the PLAYER faction (a squad member) is allowed only when the requester (speaker) is the player
// character and is not the actor itself; every other safety check is unchanged (dead/down, existing orders,
// player-given orders, missing orders receiver). Non-player actors keep the old rule: never a player character.
enum StartActorVerdict {
  START_ACTOR_OK = 0,
  START_ACTOR_DOWN,
  START_ACTOR_IS_REQUESTER,
  START_ACTOR_PLAYER_CHARACTER,
  START_ACTOR_PLAYER_FACTION_NO_PLAYER_REQUESTER,
  START_ACTOR_NO_ORDERS_RECEIVER,
  START_ACTOR_HAS_PLAYER_ORDERS,
  START_ACTOR_HAS_ORDERS
};

inline StartActorVerdict ClassifyStartActor(bool dead, bool unconscious,
                                            bool actorIsPlayerCharacter,
                                            bool actorInPlayerFaction,
                                            bool requesterIsPlayerCharacter,
                                            bool actorIsRequester,
                                            bool hasOrdersReceiver,
                                            bool hasPlayerOrders,
                                            bool orderListEmpty) {
  if (dead || unconscious) return START_ACTOR_DOWN;
  if (actorIsRequester) return START_ACTOR_IS_REQUESTER;
  const bool squadWithPlayerRequester = actorInPlayerFaction && requesterIsPlayerCharacter;
  if (actorInPlayerFaction && !requesterIsPlayerCharacter) return START_ACTOR_PLAYER_FACTION_NO_PLAYER_REQUESTER;
  if (actorIsPlayerCharacter && !squadWithPlayerRequester) return START_ACTOR_PLAYER_CHARACTER;
  if (!hasOrdersReceiver) return START_ACTOR_NO_ORDERS_RECEIVER;
  if (hasPlayerOrders) return START_ACTOR_HAS_PLAYER_ORDERS;
  if (!orderListEmpty) return START_ACTOR_HAS_ORDERS;
  return START_ACTOR_OK;
}

inline const char *StartActorSuffix(StartActorVerdict v) {
  switch (v) {
    case START_ACTOR_DOWN: return "down";
    case START_ACTOR_IS_REQUESTER: return "actor_is_requester";
    case START_ACTOR_PLAYER_CHARACTER: return "player_character";
    case START_ACTOR_PLAYER_FACTION_NO_PLAYER_REQUESTER: return "player_faction_no_player_requester";
    case START_ACTOR_NO_ORDERS_RECEIVER: return "no_orders_receiver";
    case START_ACTOR_HAS_PLAYER_ORDERS: return "has_player_orders";
    case START_ACTOR_HAS_ORDERS: return "has_orders";
    default: return "ok";
  }
}

'''
s=s.replace(anchor,policy+anchor)
io.open(p,'w',encoding='utf-8',newline='').write(s)

# 2. Start()
p,s=rw('src/NativeTravelLifecycle.cpp')
old='''    if (actor->isDead() || actor->isUnconcious() || actor->isPlayerCharacter() ||
        (faction && faction->isThePlayer()) ||
        !orders || orders->hasPlayerOrders() || !orders->orders.list.empty()) {
      reason = "npc_has_existing_orders_or_unavailable"; return false;
    }
'''
new='''    // NC17: a player-faction companion is a legal partner when the player character is the requester.
    // Unavailable/existing-orders checks are unchanged; the specific cause is appended for diagnostics.
    Character *requesterChar = Stobe::KenshiAi::ResolveCharacter(world, speaker);
    const bool requesterIsPlayer = requesterChar && !requesterChar->isDead() && requesterChar->isPlayerCharacter();
    const Stobe::NativeTravelReceiptPolicy::StartActorVerdict actorVerdict =
      Stobe::NativeTravelReceiptPolicy::ClassifyStartActor(
        actor->isDead(), actor->isUnconcious(), actor->isPlayerCharacter(),
        faction && faction->isThePlayer(), requesterIsPlayer, speaker == serial,
        orders != nullptr, orders && orders->hasPlayerOrders(), !orders || orders->orders.list.empty());
    if (actorVerdict != Stobe::NativeTravelReceiptPolicy::START_ACTOR_OK) {
      reason = std::string("npc_has_existing_orders_or_unavailable:") +
               Stobe::NativeTravelReceiptPolicy::StartActorSuffix(actorVerdict);
      return false;
    }
'''
assert s.count(old)==1
s=s.replace(old,new)
io.open(p,'w',encoding='utf-8',newline='').write(s)
