<#
gfx-sample.ps1 [-Sec 30]  (both rigs): one line of resource use while Kenshi runs, for gfx-measure.sh:
  gpu=<mean nvidia-smi utilization %> gpumem=<MB> cpu=<kenshi_x64 CPU % of the whole machine> cpu1=<% of one core>
  ram=<kenshi_x64 private MB> ws=<working set MB>
#>
param([int]$Sec = 30)
$p = Get-Process kenshi_x64 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { 'gfx-sample: kenshi_x64 not running'; exit 1 }
$smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
if (-not $smi) { $smi = 'C:\Windows\System32\nvidia-smi.exe' }
$c0 = $p.TotalProcessorTime.TotalSeconds; $t0 = Get-Date
$g = @(); $m = @()
for ($i = 0; $i -lt $Sec; $i++) {
  $o = & $smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1
  if ($o -match '(\d+),\s*(\d+)') { $g += [int]$Matches[1]; $m += [int]$Matches[2] }
  Start-Sleep -Milliseconds 1000
}
$p.Refresh()
$dt = ((Get-Date) - $t0).TotalSeconds; $cpu1 = ($p.TotalProcessorTime.TotalSeconds - $c0) / $dt * 100
$n = [Environment]::ProcessorCount
$ga = if ($g.Count) { ($g | Measure-Object -Average).Average } else { -1 }
$ma = if ($m.Count) { ($m | Measure-Object -Average).Average } else { -1 }
'gpu={0:F0} gpumem={1:F0} cpu={2:F1} cpu1={3:F0} ram={4:F0} ws={5:F0}' -f $ga, $ma, ($cpu1 / $n), $cpu1, ($p.PrivateMemorySize64 / 1MB), ($p.WorkingSet64 / 1MB)
