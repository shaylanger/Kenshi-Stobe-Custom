#!/usr/bin/env python3
"""Coordinator-only C01-C04 observations on a disposable awake two-person fixture.
No installation/launch/load/attack/movement. Physical WASD/UI/visual checks remain separate.
"""
import argparse, importlib.util, json, math, re, time
from pathlib import Path

def fields(reply):
    return dict(re.findall(r"(\w+)=([^\s]+)", reply))
def finite(row, key):
    value=float(row[key])
    if not math.isfinite(value): raise ValueError("nonfinite "+key)
    return value
def camera_matches(row):
    return row.get("actual_valid")=="1" and abs(finite(row,"actual_distance")-finite(row,"applied"))<.20

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--kah-client",required=True,type=Path); p.add_argument("--dir",required=True)
    p.add_argument("--out",required=True,type=Path)
    p.add_argument("--actor-a",required=True); p.add_argument("--actor-b",required=True)
    a=p.parse_args(); a.out.mkdir(parents=True,exist_ok=False)
    spec=importlib.util.spec_from_file_location("kah",a.kah_client)
    kah=importlib.util.module_from_spec(spec); spec.loader.exec_module(kah); folder=kah.to_local(a.dir)
    original=None; initial_distance=None; initial_actor=None; failure=None; restore_error=None; passed=[]
    def send(cmd,*args):
        ok,detail=kah.send(folder,cmd,list(args),timeout=5)
        with (a.out/"commands.jsonl").open("a") as f:
            f.write(json.dumps(dict(at=time.time(),cmd=cmd,args=args,ok=ok,detail=detail))+"\n")
        if not ok: raise RuntimeError(cmd+": "+detail)
        return detail
    def wait(cmd,predicate,*args):
        end=time.monotonic()+6
        while True:
            row=fields(send(cmd,*args))
            if predicate(row): return row
            if time.monotonic()>end: raise RuntimeError("observation deadline: "+cmd+" "+str(row))
            time.sleep(.15)
    def mode(on):
        send("fp_mode","on" if on else "off")
        wait("fp_state",lambda r:r.get("fp_mode")==str(on))
    try:
        if "phase=world" not in send("status"): raise RuntimeError("INVALID fixture not loaded")
        original=int(fields(send("fp_state"))["fp_mode"])
        initial_distance=finite(fields(send("fp_camera","state")),"target")
        initial_actor=fields(send("fp_control","state")).get("control_ids")
        mode(1); send("select",a.actor_a); send("fp_control","take")
        one=wait("fp_control",lambda r:r.get("controlled") not in ("0",None),"state")
        send("fp_camera","distance","0")
        eye=wait("fp_camera",lambda r:camera_matches(r) and finite(r,"applied")<.05,"state")
        speed=finite(eye,"speed_scale"); actor=one["controlled"]
        send("fp_camera","wheel","-720")
        far=wait("fp_camera",lambda r:camera_matches(r) and finite(r,"applied")>.75,"state")
        if far["direct"]!="1" or finite(far,"target")<2.9: raise RuntimeError("zoom/control not applied")
        if abs(finite(far,"speed_scale")-speed)>.001: raise RuntimeError("wheel changed speed")
        if fields(send("fp_control","state"))["controlled"]!=actor: raise RuntimeError("wheel changed actor")
        passed.append("C01 numeric zoom/direct ownership PASS; physical movement/visuals pending")
        passed.append("C02 wheel-distance/speed PASS; physical UI/focus scrolling pending")
        send("select",a.actor_b)
        two=wait("fp_control",lambda r:r.get("inspected") not in (actor,"0",None),"state")
        if two["controlled"]!=actor: raise RuntimeError("inspection transferred ownership")
        send("inv",a.actor_b); send("stat",a.actor_b,"all")
        passed.append("C03 selection/ownership/inventory/stat query PASS; panel visuals pending")
        send("fp_control","take")
        taken=wait("fp_control",lambda r:r.get("controlled")==two["inspected"],"state")
        if taken["control_ids"]==one["control_ids"]: raise RuntimeError("transfer identity unchanged")
        mode(0); mode(1)
        if fields(send("fp_control","state"))["controlled"]!=taken["controlled"]:
            raise RuntimeError("fallback changed pinned identity")
        passed.append("C04 transfer/fallback identity PASS; moving-release/native squad AI pending")
    except (Exception,SystemExit) as e: failure=str(e)
    finally:
        try:
            # Leave disposable fixture on actor-a; coordinator restores the fixture.
            # Only original toggle and requested camera distance are restored here.
            if initial_actor:
                send("select",a.actor_a); send("fp_control","take")
            if initial_distance is not None: send("fp_camera","distance",str(initial_distance))
            if original is not None: mode(original)
        except (Exception,SystemExit) as e: restore_error=str(e)
    result=dict(observations=passed,failure=failure,restore_error=restore_error,
                restore="FP toggle/distance restored; selected/control actor restored to actor-a; coordinator must restore disposable fixture",
                scope="numeric subset only; C01-C05 full gameplay/visual acceptance pending")
    (a.out/"summary.json").write_text(json.dumps(result,indent=2))
    line="RESULT C00 "+("FAIL" if failure or restore_error else "PASS")+" camera/control numeric subset; full acceptance pending"
    (a.out/"RESULT.txt").write_text(line+"\n"+json.dumps(result,indent=2)+"\n"); print(line)
    return 1 if failure or restore_error else 0
if __name__=="__main__": raise SystemExit(main())
