#!/usr/bin/env python3
"""P02 coordinator-only polling of a prepared native melee duel.
No install/launch/load/attack/protect/health/speed commands. Polling does not
prove every intra-frame impact; this maps native state/timer observations."""
import argparse,csv,importlib.util,json,math,re,time
from pathlib import Path
FIELDS="actor combat active state next attacking dead dead_left state_left technique finished movement target blocking_target threats frame_dt".split()
HEX={"actor","combat","technique","movement","target","blocking_target"}
FLOAT={"attacking","dead_left","state_left","frame_dt"}
def parse(detail):
    values=dict(re.findall(r"(\w+)=([^\s]+)",detail))
    if not set(FIELDS)<=values.keys():raise ValueError("incomplete melee observation")
    row={k:(int(values[k],16) if k in HEX else float(values[k]) if k in FLOAT else int(values[k])) for k in FIELDS}
    if not all(math.isfinite(row[k]) for k in FLOAT):raise ValueError("nonfinite native timer/progress")
    if not row["actor"] or not row["combat"] or not row["movement"]:raise ValueError("missing native ownership")
    if row["frame_dt"]<=0:raise ValueError("paused or invalid native game time")
    if row["state"] not in range(12):raise ValueError("unmapped native state")
    return row
def assess(rows,minimum):
    if len(rows)<20:raise ValueError("insufficient observations")
    if len({(r["actor"],r["combat"],r["movement"]) for r in rows})!=1:
        raise ValueError("actor/combat identity changed")
    if not all(r["active"] for r in rows):raise ValueError("native fight stopped")
    starts=0;was=False
    for r in rows:
        chop=r["state"]==0 and bool(r["technique"])
        if chop and not was:starts+=1
        was=chop
    if starts<minimum:raise ValueError("insufficient observed native CHOP cycles: "+str(starts))
    if not any(r["dead"] and r["dead_left"]>0 for r in rows):
        raise ValueError("native recovery timer not observed; mapping incomplete")
    return {"observed_chop_entries":starts,"states":sorted({r["state"] for r in rows}),
            "positive_recovery_samples":sum(r["dead"] and r["dead_left"]>0 for r in rows),
            "samples":len(rows),"method":"polling; no impact/callback completeness claim"}
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--kah-client",required=True,type=Path);p.add_argument("--dir",required=True)
    p.add_argument("--out",required=True,type=Path);p.add_argument("--seconds",default=60,type=float)
    p.add_argument("--min-cycles",default=3,type=int)
    a=p.parse_args()
    if not 5<=a.seconds<=120 or not 2<=a.min_cycles<=20:p.error("seconds 5..120, min-cycles 2..20")
    a.out.mkdir(parents=True,exist_ok=False)
    spec=importlib.util.spec_from_file_location("kah",a.kah_client)
    kah=importlib.util.module_from_spec(spec);spec.loader.exec_module(kah);folder=kah.to_local(a.dir)
    def send(cmd,*args):
        ok,detail=kah.send(folder,cmd,list(args),timeout=5)
        with (a.out/"commands.jsonl").open("a") as f:
            f.write(json.dumps({"at":time.time(),"cmd":cmd,"args":args,"ok":ok,"detail":detail})+"\n")
        if not ok:raise RuntimeError(cmd+": "+detail)
        return detail
    original=None;result=[];error=None
    def toggle(mode):
        send("fp_mode","on" if mode else "off");deadline=time.monotonic()+5
        while "fp_mode=%d"%mode not in send("fp_state"):
            if time.monotonic()>deadline:raise RuntimeError("FP toggle did not apply")
            time.sleep(.1)
    try:
        if "phase=world" not in send("status"):raise RuntimeError("setup=invalid world unavailable")
        m=re.search(r"fp_mode=(0|1)",send("fp_state"))
        if not m:raise RuntimeError("FP mode unavailable")
        original=int(m[1])
        if "enabled=0" not in send("fp_combat","state"):raise RuntimeError("manual adapter must remain OFF")
        for mode in (0,1):
            toggle(mode);rows=[];deadline=time.monotonic()+a.seconds
            path=a.out/("native-melee-fp%d.csv"%mode)
            with path.open("w",newline="") as f:
                writer=csv.DictWriter(f,fieldnames=["elapsed",*FIELDS]);writer.writeheader();start=time.monotonic()
                while time.monotonic()<deadline:
                    row=parse(send("fp_melee","state"));row["elapsed"]=time.monotonic()-start
                    rows.append(row);writer.writerow(row);f.flush();time.sleep(.02)
            result.append({"fp_mode":mode,**assess(rows,a.min_cycles)})
    except Exception as exc:error=str(exc)
    finally:
        if original is not None:
            try:toggle(original)
            except Exception as exc:error=(error or "")+"; restore_failed="+str(exc)
    line="RESULT P02 "+("FAIL "+error if error else "PASS "+json.dumps(result))+" polling/state mapping only; manual/impact/root motion unvalidated"
    (a.out/"RESULT.txt").write_text(line+"\n");print(line)
    return 1 if error else 0
if __name__=="__main__":raise SystemExit(main())
