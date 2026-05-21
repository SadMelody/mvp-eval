param(
  [Parameter(Mandatory = $true)]
  [string]$ReportPath,

  [string]$MetricsPath,

  [string]$Model,

  [int64]$InputTokens,

  [int64]$OutputTokens,

  [Nullable[int64]]$TotalTokens,

  [int64]$ToolCalls,

  [double]$DurationSeconds
)

$ErrorActionPreference = "Stop"

if (-not $MetricsPath -and (-not $PSBoundParameters.ContainsKey("InputTokens") -or -not $PSBoundParameters.ContainsKey("OutputTokens") -or -not $PSBoundParameters.ContainsKey("ToolCalls") -or -not $PSBoundParameters.ContainsKey("DurationSeconds"))) {
  throw "Provide -MetricsPath or all metric parameters: -InputTokens, -OutputTokens, -ToolCalls, -DurationSeconds."
}

$resolvedReport = Resolve-Path -LiteralPath $ReportPath
$report = Get-Content -Raw -LiteralPath $resolvedReport | ConvertFrom-Json

if ($MetricsPath) {
  $resolvedMetrics = Resolve-Path -LiteralPath $MetricsPath
  $metrics = Get-Content -Raw -LiteralPath $resolvedMetrics | ConvertFrom-Json
} else {
  if ($null -eq $TotalTokens) {
    $TotalTokens = $InputTokens + $OutputTokens
  }

  $metricsModel = if ([string]::IsNullOrWhiteSpace($Model)) { $null } else { $Model }

  $metrics = [pscustomobject]@{
    model = $metricsModel
    input_tokens = $InputTokens
    output_tokens = $OutputTokens
    total_tokens = $TotalTokens
    tool_calls = $ToolCalls
    duration_seconds = $DurationSeconds
  }
}

$required = @("input_tokens", "output_tokens", "total_tokens", "tool_calls", "duration_seconds")
foreach ($field in $required) {
  if ($null -eq $metrics.$field) {
    throw "Missing runner metric: $field"
  }
}

if ([int64]$metrics.total_tokens -ne ([int64]$metrics.input_tokens + [int64]$metrics.output_tokens)) {
  throw "Invalid runner metrics: total_tokens must equal input_tokens + output_tokens."
}

$report.runner_metrics = [pscustomobject]@{
  model = $metrics.model
  input_tokens = [int64]$metrics.input_tokens
  output_tokens = [int64]$metrics.output_tokens
  total_tokens = [int64]$metrics.total_tokens
  tool_calls = [int64]$metrics.tool_calls
  duration_seconds = [double]$metrics.duration_seconds
}

$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resolvedReport
Write-Output $resolvedReport
