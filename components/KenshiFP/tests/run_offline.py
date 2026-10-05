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
for name,flags in [("plain",[]),("ubsan",["-fsanitize=undefined","-fno-sanitize-recover=all"])]:
    binary=str(logs/("test_probe_"+name))
    run(name+"-compile",["gcc","-std=c11","-Wall","-Wextra","-Werror","-g",*flags,
                        str(root/"tests/test_combat_probe.c"),"-o",binary])
    run(name,[binary])
run("decoder",[sys.executable,"-m","unittest","discover","-s",str(root/"tests"),
               "-p","test_native_trace.py","-v"])
print("RESULT B08 PASS bounded plain+UBSan probe and native trace decoder checks; engine offsets/runtime not validated")
