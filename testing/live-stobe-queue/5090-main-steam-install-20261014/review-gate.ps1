function Get-PacketSha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }

function Test-CandidateReview([string]$Path,[string]$ExpectedReviewSha256,[string]$ExpectedCandidateSha256) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  if ((Get-PacketSha256 $Path) -cne $ExpectedReviewSha256.ToUpperInvariant()) { return $false }
  $text=Get-Content -LiteralPath $Path -Raw
  $clearVerdict='(?im)^Verdict:\s*\*\*CLEAR(?=\*\*|\s)[^\r\n]*?\*\*'
  if ($text -notmatch $clearVerdict) { return $false }
  if ($text -notmatch [regex]::Escape($ExpectedCandidateSha256.ToUpperInvariant())) { return $false }
  return $true
}
