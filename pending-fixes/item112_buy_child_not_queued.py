#!/usr/bin/env python3
"""Item 112 (KenshiFP): a production goal's own purchase sub-goal isn't queued behind that goal.

m18 Squin STOBE 15: approved `buy-wg-...-Fabrics` stayed "Queued behind an active production goal" (task goals
except STOCK wait while the actor has active work) while the production goal waited for the Fabrics: deadlock.
Purchase sub-goals of a work goal (id "buy-wg-...", made by the item 99 fallback) now run.
Usage: item112_buy_child_not_queued.py <KenshiFP root>
"""
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / 'client' / 'stobe_task_goals.inc'
s = p.read_text()
old = '                if(strcmp(g->kind,"STOCK")&&stg_actor_has_active_work(g->actor_serial))'
new = ('                /* Item 112: a work goal\'s own purchase sub-goal ("buy-wg-...") must run, not wait for it. */\n'
       '                if(strcmp(g->kind,"STOCK")&&strncmp(g->id,"buy-wg-",7)&&stg_actor_has_active_work(g->actor_serial))')
if new in s: print('already patched'); sys.exit(0)
assert s.count(old) == 1, 'anchor'
p.write_text(s.replace(old, new)); print('patched')
