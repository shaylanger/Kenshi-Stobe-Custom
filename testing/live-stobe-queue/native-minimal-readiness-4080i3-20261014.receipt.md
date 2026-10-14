# 4080 i3 native minimal readiness snapshot receipt

Started UTC: 2026-10-14T05:36:41.0951363Z
Finished UTC: 2026-10-14T05:36:41.2906155Z
Exit code: 1
Hashes rechecked immediately before execution: all four matched Validator clearance.
Scope: one read-only setup snapshot; not a gameplay test and does not verify session authorization.

## Output
```text
Test-Path : Access is denied
At C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1:194 char:15
+     if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw ...
+               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : PermissionDenied: (C:\Users\Shay\.ssh\config:String) [Test-Path], UnauthorizedAccessExce 
   ption
    + FullyQualifiedErrorId : ItemExistsUnauthorizedAccessError,Microsoft.PowerShell.Commands.TestPathCommand
 
```

