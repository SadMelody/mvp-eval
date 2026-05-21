param(
  [Parameter(Mandatory = $true)]
  [string]$EventPath,

  [Parameter(Mandatory = $true)]
  [double]$DurationSeconds,

  [string]$Model
)

$ErrorActionPreference = "Stop"

$resolvedEventPath = Resolve-Path -LiteralPath $EventPath
$usage = $null
$toolCalls = 0

foreach ($line in Get-Content -LiteralPath $resolvedEventPath) {
  $trimmed = "$line".Trim()
  if (-not $trimmed.StartsWith("{")) {
    continue
  }

  try {
    $event = $trimmed | ConvertFrom-Json
  } catch {
    continue
  }

  if ($event.type -eq "turn.completed" -and $null -ne $event.usage) {
    $usage = $event.usage
  }

  if ($event.type -eq "item.completed" -and $null -ne $event.item -and ($event.item.type -match "tool|command|function")) {
    $toolCalls += 1
  }
}

if ($null -eq $usage) {
  throw "No usage event found in $resolvedEventPath."
}

foreach ($field in @("input_tokens", "output_tokens")) {
  if ($null -eq $usage.$field) {
    throw "Usage event is missing $field in $resolvedEventPath."
  }
}

$inputTokens = [int64]$usage.input_tokens
$outputTokens = [int64]$usage.output_tokens
$totalTokens = $inputTokens + $outputTokens

[pscustomobject]@{
  model = if ([string]::IsNullOrWhiteSpace($Model)) { $null } else { $Model }
  input_tokens = $inputTokens
  output_tokens = $outputTokens
  total_tokens = $totalTokens
  tool_calls = [int64]$toolCalls
  duration_seconds = [double]$DurationSeconds
  cached_input_tokens = $usage.cached_input_tokens
  reasoning_output_tokens = $usage.reasoning_output_tokens
} | ConvertTo-Json -Depth 8
