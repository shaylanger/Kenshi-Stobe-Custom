import pathlib,sys
p=pathlib.Path(sys.argv[1])/'src/WorldCommands.inc'; s=p.read_bytes().decode()
old='''      u->powerTimeStored = u->_powerTimeStoreMax;
    } else if (what == "supply"'''
new='''      u->powerTimeStored = u->_powerTimeStoreMax;
    } else if (what == "drain") { // empties a battery (tests can then see `charge` or the grid refill it)
      UseableStuff *u = dynamic_cast<UseableStuff *>(b);
      if (!Valid(u) || !u->isBattery()) {
        out = b->getName() + " is not a battery";
        return true;
      }
      u->powerTimeStored = 0;
    } else if (what == "supply"'''
nl='\r\n' if '\r\n' in s else '\n'
old=old.replace('\n',nl); new=new.replace('\n',nl)
assert s.count(old)==1
s=s.replace(old,new)
for a in ('on|off|charge|supply|unsupply',):
    s=s.replace(a,'on|off|charge|drain|supply|unsupply')
p.write_bytes(s.encode())
d=pathlib.Path(sys.argv[1])/'docs/COMMANDS.md'; t=d.read_bytes().decode()
o='| `power <building> on\|off\|charge\|supply\|unsupply [radius <m>]` | switch power; `charge` fills a battery'
assert t.count(o)==1
t=t.replace(o,'| `power <building> on\|off\|charge\|drain\|supply\|unsupply [radius <m>]` | switch power; `charge` fills a battery, `drain` empties one (read `battery=<charge>/<max>` in the reply)')
d.write_bytes(t.encode())
print('ok')
