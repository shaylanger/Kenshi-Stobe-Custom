#!/usr/bin/env python3
"""Bug 115: goal meals used up food without feeding her.

Run 9: Malzin "ate" 6 Dried Meat from a chest via Character::eatItem and
her level went 130 -> 146 (fed stayed 0.0); from her pack 2 items gave +1
in total. The game's own eating gave +14 for one Dried Meat. So eatItem
consumes the item without the meal. New meal step: with food in her pack
the game feeds her (KenshiFP waits a game minute and looks again); with
food in storage she walks there and takes up to 3 food items into her pack.

Usage: patch_r21_bug115_meal_game_eats.py <KenshiFP root>   (idempotent)
"""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
text = path.read_text(encoding='utf-8')
if 'bug 115' in text:
    print('already patched')
    sys.exit(0)
edits = [
    ("""    if(own&&stg_count_matching(own,"food")>0){
        if(sgm_eat_one(actor,own)){m->eaten++;m->next_ms=now+4000;logline("[stobe] GOAL_MEAL ate from her pack actor=%s level=%.0f",name,lvl);}
        else{m->eating=0;logline("[stobe] GOAL_MEAL could not eat from her pack actor=%s",name);return 0;}
        snprintf(step,stepsz,"Eating (hungry)");return 1;
    }
""",
     """    if(own&&stg_count_matching(own,"food")>0){
        /* bug 115: eatItem used the food up without the meal (~+1 per Dried Meat,
         * the game's own eating gives ~+14). With food in her pack the game feeds her. */
        logline("[stobe] GOAL_MEAL food in her pack; the game feeds her actor=%s level=%.0f",name,lvl);
        m->eating=0;m->retry_ms=now+SGM_PACK_RETRY_MS;return 0;
    }
"""),
    ("""    if(sgm_eat_one(actor,wgp_building_inventory(store))){m->eaten++;m->next_ms=now+4000;m->last_d=0;m->still=0;logline("[stobe] GOAL_MEAL ate from %s actor=%s level=%.0f",sn,name,lvl);}
    else{m->eating=0;logline("[stobe] GOAL_MEAL could not eat from %s actor=%s",sn,name);return 0;}
    snprintf(step,stepsz,"Eating at %s (hungry)",sn[0]?sn:"storage");
    return 1;
""",
     """    { /* bug 115: take food into her pack; the game feeds her from there */
        int took=stg_transfer_to_character(wgp_building_inventory(store),actor,"food",SGM_TAKE_FOOD);
        m->eating=0;m->last_d=0;m->still=0;
        if(took>0){m->retry_ms=now+SGM_PACK_RETRY_MS;logline("[stobe] GOAL_MEAL took %d food from %s actor=%s level=%.0f",took,sn,name,lvl);}
        else logline("[stobe] GOAL_MEAL could not take food from %s actor=%s",sn,name);
        return 0;
    }
"""),
    ("#define SGM_NOFOOD_RETRY_MS 600000 /* bug 92: no food anywhere -> look again in 10 game min */\n",
     "#define SGM_NOFOOD_RETRY_MS 600000 /* bug 92: no food anywhere -> look again in 10 game min */\n"
     "#define SGM_PACK_RETRY_MS 60000 /* bug 115: food in her pack -> the game eats; look again in 1 game min */\n"
     "#define SGM_TAKE_FOOD 3\n"),
]
for old, new in edits:
    assert text.count(old) == 1, 'anchor not found exactly once: %r' % old[:70]
    text = text.replace(old, new)
path.write_text(text, encoding='utf-8', newline='')
print('patched', path)
