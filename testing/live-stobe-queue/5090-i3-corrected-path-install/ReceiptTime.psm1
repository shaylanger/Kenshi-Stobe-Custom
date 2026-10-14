Set-StrictMode -Version Latest

function ConvertFrom-PinnedReceiptUtc {
  [CmdletBinding()]
  param([Parameter(Mandatory=$true)][string]$Json)

  # ConvertFrom-Json may infer an ISO timestamp as DateTime. Casting that object
  # back to string can discard or reinterpret the original UTC offset depending
  # on host PowerShell/local timezone. Read the JSON string token verbatim.
  $found = [regex]::Matches($Json, '"issued_utc"\s*:\s*"(?<value>[^"\\]*)"')
  if ($found.Count -ne 1) { throw 'Receipt must contain exactly one plain-string issued_utc property.' }
  $value = $found[0].Groups['value'].Value
  if ($value -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z') {
    throw 'Receipt issued_utc must be ISO-8601 with an explicit UTC designator or offset.'
  }
  try {
    return [DateTimeOffset]::Parse($value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
  } catch {
    throw "Receipt issued_utc is not a valid timestamp: $value"
  }
}

Export-ModuleMember -Function ConvertFrom-PinnedReceiptUtc
