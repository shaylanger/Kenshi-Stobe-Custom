# Relationship pricing: server interface for Stobe.dll's shop-window hook (item 104)

Server side is live (StobeServer `1c2457f`). This is the contract for the native builder.

## What the hook needs

Kenshi's own shop prices, for every trader, adjusted by **r**. r is that shopkeeper's relationship value toward the
squad member who is trading, from -100 to 100. No history means r = 0, which is the vanilla price.

## Endpoint (read-only, cheap)

`GET http://<server>/StobeServer/relationship_pricing.php?player=<trading character>&npcs=<id>|<id>|...`

- `player`: the name of the squad member doing the trade (e.g. `Beaks`). If empty, the server uses `PLAYER_NAME`.
- `npcs`: up to 64 ids separated by `|`. Each id is the trader's **name** as Stobe sends it in chat/events
  (e.g. `Apothecary Abia`), or the trader's **hand serial** (digits, or `hand_<serial>`; matched against
  `core_npc_master.metadata.storage_id`).
- Reply (JSON):

```json
{"ok":true,"player":"Shay",
 "constants":{"buy_discount_max":0.3,"buy_discount_exp":1.1,"buy_increase_max":10,"buy_increase_exp":2.32,
              "sell_bonus_max":0.1,"sell_bonus_exp":1.1,"sell_cut_max":0.75,"sell_cut_exp":2.32,
              "trader_buy_ratio":0.5},
 "entries":[{"query":"Apothecary Abia","npc":"Apothecary Abia","found":true,"r":9,
             "buy_factor":0.9788,"sell_factor":1.0071}]}
```

- `found:false` means the server has no profile for that NPC: r = 0, factors 1.0.
- Measured on this PC: about 20 ms for 3 NPCs.

## Formula (the hook may compute it from `constants`, or just use the two factors)

- **Player buys from the trader:** price = vanilla sell price × `buy_factor`.
  - r > 0: `1 - buy_discount_max * (r/100)^buy_discount_exp`, which is -2.4% at +10, -15.85% at +56, -30% at +100.
  - r < 0: `1 + buy_increase_max * (|r|/100)^buy_increase_exp`, which is +4.8% at -10, +200% at -50, +1000% at -100.
- **Player sells to the trader:** price = vanilla buy price × `sell_factor`.
  - r > 0: `1 + sell_bonus_max * (r/100)^sell_bonus_exp`, up to +10% at +100.
  - r < 0: `1 - sell_cut_max * (|r|/100)^sell_cut_exp`, down to -75% at -100. This max is **proposed; Shay to confirm**.
- **Anti-exploit floor (the hook must apply it):** for each item, the adjusted buy price is never lower than either:
  1. what that trader pays the player for the same item right now (vanilla buy price × `sell_factor`), plus 1;
  2. the trader's vanilla buy price for it.

  This rules out a buy/sell loop profit, including after small relationship gains.

## Caching and when to call

- r changes only after chats, fights and deal outcomes, so caching per (trader, trading character) is fine.
- Suggested: call once when a trade window opens, for that trader and the trading character, and use the factors
  until the window closes.
- Optional: a short-lived cache keyed by trader serial (60 s).
- If the server is unreachable or the reply has `ok:false`, use vanilla prices (factors 1.0). Never block the UI.

## Server-side rules already enforced (for reference)

- **Deals negotiated through STOBE dialogue** get the same prices: a cheaper ACCEPT becomes her counter at her price.
- **Willingness:**
  - no trade at r <= -80;
  - pay-later only at r >= 0;
  - free favours at r >= 30;
  - free items/Cats at r >= 56.
- **Weapon guard:** an outsider gives up, drops or stows her weapon only at r >= 70.

The shop-window hook may also want to refuse trade at r <= -80 (open the window empty, or show a refusal message).
That is a design choice for Shay and the native builder; the server exposes r for it.
