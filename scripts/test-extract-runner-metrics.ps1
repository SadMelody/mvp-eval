param()

$ErrorActionPreference = "Stop"

function Add-Result {
  param(
    [System.Collections.Generic.List[object]]$Results,
    [string]$Name,
    [bool]$Passed,
    [string]$Summary
  )

  $Results.Add([pscustomobject]@{
    name = $Name
    passed = $Passed
    summary = $Summary
  }) | Out-Null
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$sampleEventPath = Join-Path $root "fixtures\codex-events.sample.jsonl"
$results = [System.Collections.Generic.List[object]]::new()

$metricsJson = & (Join-Path $PSScriptRoot "extract-runner-metrics.ps1") `
  -EventPath $sampleEventPath `
  -DurationSeconds 12.5 `
  -Model "test-model"
$metrics = $metricsJson | ConvertFrom-Json

Add-Result $results "extract_metrics.input_tokens" ([int64]$metrics.input_tokens -eq 111) "expected 111, actual $($metrics.input_tokens)"
Add-Result $results "extract_metrics.output_tokens" ([int64]$metrics.output_tokens -eq 22) "expected 22, actual $($metrics.output_tokens)"
Add-Result $results "extract_metrics.total_tokens" ([int64]$metrics.total_tokens -eq 133) "expected 133, actual $($metrics.total_tokens)"
Add-Result $results "extract_metrics.tool_calls" ([int64]$metrics.tool_calls -eq 2) "expected 2, actual $($metrics.tool_calls)"
Add-Result $results "extract_metrics.duration_seconds" ([double]$metrics.duration_seconds -eq 12.5) "expected 12.5, actual $($metrics.duration_seconds)"
Add-Result $results "extract_metrics.model" ([string]$metrics.model -eq "test-model") "expected test-model, actual $($metrics.model)"
Add-Result $results "extract_metrics.cached_input_tokens" ([int64]$metrics.cached_input_tokens -eq 10) "expected 10, actual $($metrics.cached_input_tokens)"
Add-Result $results "extract_metrics.reasoning_output_tokens" ([int64]$metrics.reasoning_output_tokens -eq 3) "expected 3, actual $($metrics.reasoning_output_tokens)"

$failed = @($results | Where-Object { -not $_.passed })
$status = if ($failed.Count -eq 0) { "passed" } else { "failed" }

[pscustomobject]@{
  status = $status
  sample_event_path = $sampleEventPath
  checks = $results
} | ConvertTo-Json -Depth 8

if ($failed.Count -gt 0) {
  exit 1
}
