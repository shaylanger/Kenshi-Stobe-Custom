<# Restore only this packet's two Main Steam Stobe files. Plan-only unless -Apply. #>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^mainsteam-769859-\d{8}T\d{6}Z$')][string]$OperationId,[switch]$Apply)
$ErrorActionPreference = 'Stop'
$candidateSha = '769859CB364D1C719F94FC465265BEF9C7EF6803D40FAD7F6B695E8425354E9A'
$targets = @(
  [pscustomobject]@{ Path='D:\Steam\steamapps\common\Kenshi\RE_Kenshi\mods\Stobe\Stobe.dll'; Baseline='AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'; Label='RE_Kenshi' },
  [pscustomobject]@{ Path='D:\Steam\steamapps\common\Kenshi\mods\Stobe\Stobe.dll'; Baseline='AEF84C0A682DF036EB2CD0DC30A809E52E19956933F142C3A1D5877C4EB1907C'; Label='root-mods' }
)
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Assert-NoReparsePath([string]$Path) {
  $full=[IO.Path]::GetFullPath($Path); $drive=[IO.Path]::GetPathRoot($full); $cur=$drive.TrimEnd('\')
  foreach($part in $full.Substring($drive.Length).TrimEnd('\').Split('\')) {
    $cur=Join-Path $cur $part
    if(-not(Test-Path -LiteralPath $cur)){throw "Expected exact path component missing: $cur"}
    $item=Get-Item -LiteralPath $cur -Force
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Reparse point forbidden on exact target chain: $cur"}
  }
}
function Assert-KenshiStopped {
  try{$running=@(Get-Process -Name 'kenshi_x64' -ErrorAction Stop)}catch{
    if($_.Exception.Message -like 'Cannot find a process with the name*'){return}
    throw "Cannot establish that Kenshi is stopped: $($_.Exception.Message)"
  }
  if($running.Count){throw 'Kenshi is running; close the game before rollback.'}
}
Assert-KenshiStopped
foreach($t in $targets){
  Assert-NoReparsePath $t.Path
  if(-not(Test-Path -LiteralPath $t.Path -PathType Leaf)){throw "Target missing: $($t.Path)"}
  $backup=$t.Path+'.pre-'+$OperationId+'.bak'
  $current=Get-Sha $t.Path
  if($current -cne $candidateSha -and $current -cne $t.Baseline){throw "Rollback CAS refused for $($t.Label): target=$current"}
  if(Test-Path -LiteralPath $backup){Assert-NoReparsePath $backup}
  if($current -ceq $candidateSha -and (-not(Test-Path -LiteralPath $backup -PathType Leaf) -or (Get-Sha $backup) -cne $t.Baseline)){throw "Rollback CAS refused for $($t.Label): expected original backup missing or hash-mismatched."}
  if($current -ceq $t.Baseline -and (Test-Path -LiteralPath $backup) -and (Get-Sha $backup) -cne $t.Baseline){throw "Unexpected backup content for $($t.Label)."}
  $t | Add-Member -NotePropertyName Current -NotePropertyValue $current
  $t | Add-Member -NotePropertyName Backup -NotePropertyValue $backup
  $t | Add-Member -NotePropertyName Displaced -NotePropertyValue ($t.Path+'.rolled-back-candidate-'+$OperationId+'.dll')
  if(Test-Path -LiteralPath $t.Displaced){Assert-NoReparsePath $t.Displaced}
  if($current -ceq $candidateSha -and (Test-Path -LiteralPath $t.Displaced)){throw "Refusing to overwrite displaced candidate: $($t.Displaced)"}
}
"PLAN: rollback operation=$OperationId candidate=$candidateSha"
foreach($t in $targets){"PLAN: $($t.Label) target=$($t.Path) current=$($t.Current) backup=$($t.Backup) restored_sha=$($t.Baseline)"}
if(-not $Apply){'No files changed. Pass -Apply only if the current file is still this operation candidate.';exit 0}
Assert-KenshiStopped
# Revalidate the entire pair before the first change, then CAS each replacement.
foreach($t in $targets){
  Assert-NoReparsePath $t.Path
  if((Get-Sha $t.Path) -cne $t.Current){throw "Target changed after rollback preflight: $($t.Label)"}
  if($t.Current -ceq $candidateSha -and (Get-Sha $t.Backup) -cne $t.Baseline){throw "Backup changed after rollback preflight: $($t.Label)"}
}
foreach($t in $targets){
  if($t.Current -ceq $t.Baseline){continue}
  Assert-KenshiStopped
  Assert-NoReparsePath $t.Path
  Assert-NoReparsePath $t.Backup
  if(Test-Path -LiteralPath $t.Displaced){Assert-NoReparsePath $t.Displaced;throw "Refusing to overwrite displaced candidate: $($t.Displaced)"}
  if((Get-Sha $t.Path) -cne $candidateSha -or (Get-Sha $t.Backup) -cne $t.Baseline){throw "Rollback CAS refused at replacement: $($t.Label)"}
  [IO.File]::Replace($t.Backup,$t.Path,$t.Displaced,$true)
  if((Get-Sha $t.Path) -cne $t.Baseline -or (Get-Sha $t.Displaced) -cne $candidateSha){throw "Rollback post-write verification failed: $($t.Label)"}
}
'ROLLBACK PASS: both targets equal their exact AEF baselines; candidate retained as displaced file.'
