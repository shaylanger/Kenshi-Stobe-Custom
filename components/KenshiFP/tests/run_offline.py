#!/usr/bin/env python3
"""Run bounded offline probe checks in Linux/WSL; never invokes Kenshi."""
from pathlib import Path
import argparse,resource,subprocess,tempfile,sys
p=argparse.ArgumentParser(); p.add_argument("--out",type=Path)
args=p.parse_args(); root=Path(__file__).resolve().parent.parent
tmp=tempfile.TemporaryDirectory(prefix="kfp-combat-offline-")
logs=args.out or Path(tmp.name); logs.mkdir(parents=True,exist_ok=True)
def limit():
    resource.setrlimit(resource.RLIMIT_FSIZE,(1024*1024,1024*1024))
    resource.setrlimit(resource.RLIMIT_CPU,(15,15))
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
def run(name,cmd):
    log=logs/(name+".log")
    with log.open("wb") as out:
        try:
            result=subprocess.run(cmd,stdout=out,stderr=subprocess.STDOUT,timeout=20,preexec_fn=limit)
            code=result.returncode
        except subprocess.TimeoutExpired: code=124
    print(name,"exit="+str(code)); print(log.read_text(errors="replace")[:3000])
    if code: raise SystemExit(1)
for source in ("test_combat_probe.c","test_control_view.c","test_combat_controller.c","test_aim_geometry.c","test_melee_observe.c","test_combat_melee.c","test_combat_input.c","test_combat_trace.c","test_combat_target.c","test_combat_body.c","test_wound_geometry.c","test_shot_geometry.c","test_cmd_args.c","test_ready_latch.c","test_free_key.c"):
    for name,flags in [("plain",[]),("ubsan",["-fsanitize=undefined","-fno-sanitize-recover=all"])]:
        label=Path(source).stem+"-"+name
        binary=str(logs/label)
        run(label+"-compile",["gcc","-std=c11","-Wall","-Wextra","-Werror","-g",*flags,
                             str(root/"tests"/source),"-lm","-o",binary])
        run(label,[binary])
run("decoder",[sys.executable,"-m","unittest","discover","-s",str(root/"tests"),
               "-p","test_native_trace.py","-v"])
run("melee-decoder",[sys.executable,"-m","unittest","discover","-s",str(root/"tests"),
               "-p","test_melee_trace.py","-v"])
print("RESULT B08 PASS bounded plain+UBSan probe and native trace decoder checks; engine offsets/runtime not validated")
