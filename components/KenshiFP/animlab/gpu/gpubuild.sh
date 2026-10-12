#!/bin/bash
# gpubuild.sh <adapter.d build dir> <name> -- GPU build of the exact source of a CPU adapter (gpu-lab 2026-10-11). Git Bash.
#   WSL: build.sh --preprocess --built <dir> -> gpugen.py -> /root/gpu-lab/<name>/cpu (CPU half: capture + dump)
#   Windows: clang C -> PTX (sm_120 + sm_89 for the 4080), ptxas -c + nvlink -> C:/KenshiTestRuns/gpu-lab/gen/<name>/dev_<sm>.cubin
#   (whole-program ptxas -O1+ hits an internal compiler error on this TU; relocatable compile + nvlink: ~6 s)
# Safety: running the result is governed by the GPU SAFETY RULE in kfpgpu.py (4080 first, lanes held, compute-sanitizer).
set -e
D=$1; N=$2; W=/c/KenshiTestRuns/gpu-lab/gen/$N; G=C:/KenshiModding/components/KenshiFP/animlab/gpu
CU="/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.0"
MSYS_NO_PATHCONV=1 wsl.exe -d DwemerAI4Skyrim3 -u root --cd / -- bash -s <<WEOF
set -e; A=/mnt/c/KenshiModding/components/KenshiFP/animlab; G=\$A/gpu; O=/root/gpu-lab/$N; mkdir -p \$O
bash \$A/build.sh --preprocess --built $D --out \$O/tu >/dev/null
python3 \$G/gpugen.py \$O/tu.i \$O --inject \$G/hook_elb.inc --rename-def vm_elb_pref=vm_elb_pref__orig --cpu-tail \$G/hook_elb_cpu.inc --cpu-tail \$G/hook_loop_cpu.inc --dev-tail \$G/hook_elb_dev.inc --dev-tail \$G/hook_loop_dev.inc | tail -1
gcc -O2 -std=gnu11 -w -I\$G -o \$O/cpu \$O/cpu.c -lm
mkdir -p /mnt/c/KenshiTestRuns/gpu-lab/gen/$N && cp \$O/dev.c \$O/globals.tsv \$O/funcs.tsv /mnt/c/KenshiTestRuns/gpu-lab/gen/$N/
WEOF
cd "$W"
for sm in 120 89; do
  "/c/Program Files/LLVM/bin/clang" --target=nvptx64-nvidia-cuda -march=sm_$sm -O2 -ffp-contract=off -fno-builtin -nogpulib -w -I$G \
    -Xclang -mlink-builtin-bitcode -Xclang "$CU/nvvm/libdevice/libdevice.10.bc" -S dev.c -o dev_$sm.ptx
  "$CU/bin/ptxas.exe" -arch=sm_$sm -O3 -c dev_$sm.ptx -o dev_$sm.reloc.cubin
  "$CU/bin/nvlink.exe" -arch=sm_$sm dev_$sm.reloc.cubin -o dev_$sm.cubin 2>&1 | grep -v 'cannot be statically determined' || true
done
ls -la dev_*.cubin
