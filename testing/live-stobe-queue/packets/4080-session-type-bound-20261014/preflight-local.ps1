param([string]$BodyPath = "$PSScriptRoot\body.sh")
$ErrorActionPreference = 'Stop'
$wrapper = 'C:\KenshiModding\tools\automation\remote-bash-stdin-4080.ps1'
if ((Get-FileHash $wrapper -Algorithm SHA256).Hash -ne '138460C012FEBA82314D39013B60D1ADD6B060ACAB561A31C2DB045E894E7354') { throw 'Wrapper pin mismatch' }
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($wrapper, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Wrapper parse failure' }
$function = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-IsolatedI3Body' }, $true)
if ($null -eq $function) { throw 'Exact guard missing' }
# Evaluate only the pinned pure assertion definition, never the wrapper entry point.
& ([scriptblock]::Create($function.Extent.Text + "`nAssert-IsolatedI3Body ([IO.File]::ReadAllText('$BodyPath'))"))
Write-Output 'RESULT PACKET-ROUTE-GUARD PASS complete exact wrapper assertion; no transport invoked'
