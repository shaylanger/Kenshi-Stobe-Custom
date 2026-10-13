# Dedicated 4080-only model. Before launch: pause private requests, verify game/model capacity.
# Reviewed 24-layer fit: 14,048 prompt/51 output, >=2670MiB free VRAM and >=7041MiB free RAM.
# ValidateOnly never starts a process. Never substitute another GGUF or change original8080.
param([string]$ModelPath='C:\KenshiTestRuns\standalone4080\qwen4b.gguf',[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$dir='C:\KenshiTestRuns\standalone4080'
$expected=Join-Path $dir 'qwen4b.gguf'
if([IO.Path]::GetFullPath($ModelPath) -ne $expected){throw 'Wrong model path: only reviewed 4B asset permitted'}
if((Get-Item -LiteralPath $ModelPath).Length -ne 2497281120){throw 'Wrong model size'}
if((Get-FileHash -LiteralPath $ModelPath -Algorithm SHA256).Hash -ne '3605803B982CB64AEAD44F6C1B2AE36E3ACDB41D8E46C8A94C6533BC4C67E597'){throw 'Wrong model hash'}
if($ValidateOnly){'MODEL_GUARD_PASS';return}
if(Get-NetTCPConnection -LocalPort 18095 -State Listen -ErrorAction SilentlyContinue){throw 'Port18095 occupied; do not start another model'}
$args=@('-m',$ModelPath,'--no-mmproj','-c','24576','-ngl','24','--fit','off','-fa','on','-ctk','q4_0','-ctv','q4_0','--host','127.0.0.1','--port','18095','--parallel','1','--reasoning','off','-b','128','-ub','64','--threads','6','--threads-batch','6','--prio','-1','--log-file',"$dir\model18095.log")
$p=Start-Process 'C:\Users\Shay\StobeLocalLLM\llama-cuda\llama-server.exe' -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput "$dir\model.stdout.txt" -RedirectStandardError "$dir\model.stderr.txt"
$p.PriorityClass='BelowNormal'
$p.Id | Set-Content "$dir\model18095.pid"
$command=(Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)").CommandLine
if($command -notlike "*$expected*" -or $command -notmatch '--port 18095'){Stop-Process -Id $p.Id -Force;throw 'Postlaunch command ownership mismatch'}
$p.WaitForExit();$p.ExitCode|Set-Content "$dir\model18095.exit"

