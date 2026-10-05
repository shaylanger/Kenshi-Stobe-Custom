#!/usr/bin/env python3
"""P01: coordinator-only native lifecycle capture, using the existing kah client.
Does not install, launch, load, equip, order attacks, heal or change game speed.
A disposable, selected crossbow actor already fighting is a setup prerequisite.
"""
import argparse, csv, importlib.util, json, re, sys, time
from pathlib import Path

FIELDS = "seq ms frame kind actor ranged gun target state mode ammo stat dt".split()
def parse_page(detail, capture, after):
    meta = {k:int(v) for k,v in re.findall(r"(capture|next|oldest|lost|count|through|more)=(\d+)",detail)}
    if set(meta) != {"capture","next","oldest","lost","count","through","more"}:
        raise ValueError("incomplete page header/footer")
    if meta["capture"] != capture or meta["lost"]:
        raise ValueError("capture reset or lost records")
    if meta["oldest"]<1 or meta["next"]-meta["oldest"]!=meta["count"] or meta["through"]>=meta["next"]:
        raise ValueError("inconsistent sequence bounds")
    if bool(meta["more"]) != (meta["through"]<meta["next"]-1):
        raise ValueError("inconsistent pagination flag")
    rows=[]
    for token in detail.split():
        if "," not in token: continue
        parts=token.split(",")
        if len(parts)!=len(FIELDS): raise ValueError("truncated/invalid CSV event")
        row=dict(zip(FIELDS,parts))
        for k in ("seq","ms","frame","kind","state","mode","ammo","stat"): row[k]=int(row[k])
        for k in ("actor","ranged","gun","target"): row[k]=int(row[k],16)
        row["dt"]=float(row["dt"])
        if row["seq"] != after+len(rows)+1: raise ValueError("sequence gap/duplicate")
        rows.append(row)
    if meta["through"] != after+len(rows) or len(rows)>64:
        raise ValueError("page footer/row mismatch")
    if meta["more"] and not rows: raise ValueError("pagination made no progress")
    return meta, rows

def assess(rows, minimum):
    if not rows: raise ValueError("no native events")
    actors={r["actor"] for r in rows if r["actor"]}
    if len(actors)!=1: raise ValueError("missing or changing actor")
    if any(not r["actor"] for r in rows): raise ValueError("actor unavailable during capture")
    animation=sum(r["kind"]==2 for r in rows)
    if not animation: raise ValueError("native animation hook absent")
    before=None; shots=0; reloads=0; previous_ammo=None; gun=None
    for r in rows:
        if r["kind"] in (2,3,4) and (not r["gun"] or r["ammo"]<0 or r["state"]<0):
            raise ValueError("native gun/state/ammo unreadable")
        if r["gun"]:
            if gun is not None and r["gun"]!=gun: raise ValueError("weapon changed")
            gun=r["gun"]
        if r["ammo"]>=0:
            if previous_ammo is not None and r["ammo"]>previous_ammo: reloads+=1
            previous_ammo=r["ammo"]
        if r["kind"]==3:
            if before is not None: raise ValueError("unpaired/reentrant shot")
            before=r
        elif r["kind"]==4:
            if before is None: raise ValueError("shot after missing before")
            if (r["actor"],r["gun"],r["target"],r["stat"]) != (before["actor"],before["gun"],before["target"],before["stat"]):
                raise ValueError("shot identity/argument mismatch")
            if before["ammo"]<=0 or r["ammo"] != before["ammo"]-1:
                raise ValueError("shot callback without one observed ammo consumption")
            shots+=1; before=None
    if before is not None: raise ValueError("unfinished shot")
    if shots<minimum or reloads<minimum-1:
        raise ValueError("insufficient shot/replenishment cycles: shots=%d ammo_increases=%d"%(shots,reloads))
    return {"shots":shots,"ammo_increases":reloads,"animation_callbacks":animation,
            "raw_states":sorted({r["state"] for r in rows if r["state"]>=0})}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--kah-client",required=True,type=Path)
    p.add_argument("--dir",required=True)
    p.add_argument("--out",required=True,type=Path)
    p.add_argument("--seconds",type=float,default=60)
    p.add_argument("--min-shots",type=int,default=3)
    args=p.parse_args()
    if not 5<=args.seconds<=120 or not 2<=args.min_shots<=20: p.error("seconds 5..120; min-shots 2..20")
    args.out.mkdir(parents=True,exist_ok=False)
    spec=importlib.util.spec_from_file_location("kah",args.kah_client)
    kah=importlib.util.module_from_spec(spec); spec.loader.exec_module(kah)
    folder=kah.to_local(args.dir); transcript=args.out/"commands.jsonl"
    def send(cmd,*items):
        ok,detail=kah.send(folder,cmd,list(items),timeout=5)
        with transcript.open("a") as f: f.write(json.dumps({"at":time.time(),"cmd":cmd,"args":items,"ok":ok,"detail":detail})+"\n")
        if not ok: raise RuntimeError(cmd+": "+detail)
        return detail
    original=None; results=[]; failed=None; restore_failed=None
    try:
        status=send("status")
        if "phase=world" not in status: raise RuntimeError("setup=invalid not in world")
        state=send("fp_state")
        found=re.search(r"fp_mode=(0|1)",state)
        if not found: raise RuntimeError("unknown fp_state")
        original=int(found[1])
        for mode in (0,1):
            send("fp_mode","on" if mode else "off")
            deadline=time.monotonic()+5
            while "fp_mode=%d"%mode not in send("fp_state"):
                if time.monotonic()>deadline: raise RuntimeError("FP toggle not applied")
                time.sleep(.2)
            for cmd,items in [("status",()),("where",("@selected",)),("inv",("@selected",)),
                              ("hp",("@selected","detail")),("stat",("@selected","crossbows")),
                              ("stat",("@selected","perception")),("stat",("@selected","dexterity")),
                              ("stat",("@selected","precisionfriendlyfire"))]:
                send(cmd,*items)
            begin=send("fp_combat_probe","begin")
            found=re.search(r"capture=(\d+)",begin)
            if not found: raise RuntimeError("capture ID missing")
            capture=int(found[1]); after=0; rows=[]
            csv_path=args.out/("native-fp%d.csv"%mode)
            with csv_path.open("w",newline="") as f:
                csv.DictWriter(f,fieldnames=FIELDS).writeheader()
            def drain():
                nonlocal after
                for _ in range(16):
                    detail=send("fp_combat_probe","events",str(after))
                    meta,page=parse_page(detail,capture,after)
                    rows.extend(page); after=meta["through"]
                    with csv_path.open("a",newline="") as f:
                        csv.DictWriter(f,fieldnames=FIELDS).writerows(page)
                    if not meta["more"]: return
                raise RuntimeError("trace cannot be drained before new events")
            deadline=time.monotonic()+args.seconds
            while time.monotonic()<deadline:
                drain(); time.sleep(.25)
            send("fp_combat_probe","end"); drain()
            with (args.out/("native-fp%d.csv"%mode)).open("w",newline="") as f:
                w=csv.DictWriter(f,fieldnames=FIELDS); w.writeheader(); w.writerows(rows)
            summary=assess(rows,args.min_shots)
            results.append({"fp_mode":mode,**summary})
            send("hp","@selected","detail"); send("inv","@selected")
        (args.out/"summary.json").write_text(json.dumps(results,indent=2)+"\n")
    except (Exception,SystemExit) as exc: failed=str(exc)
    finally:
        try:
            send("fp_combat_probe","end")
            if original is not None:
                send("fp_mode","on" if original else "off")
                deadline=time.monotonic()+5
                while "fp_mode=%d"%original not in send("fp_state"):
                    if time.monotonic()>deadline: raise RuntimeError("FP restore not applied")
                    time.sleep(.2)
        except (Exception,SystemExit) as exc: restore_failed=str(exc)
    if failed or restore_failed:
        line="RESULT P01 FAIL "+json.dumps({"failure":failed,"restore_failure":restore_failed})
        code=1
    else:
        line="RESULT P01 PASS "+json.dumps(results)+" native lifecycle capture only; manual combat/body-part mapping/balance unvalidated"
        code=0
    print(line); (args.out/"RESULT.txt").write_text(line+"\n")
    return code
if __name__=="__main__": sys.exit(main())
