param(
  [string]$ReadmePath = ".\README.md",
  [string]$ResultsDir = ".\results",
  [string]$CasesPath = ".\cases.json"
)

$ErrorActionPreference = "Stop"

function Format-Number {
  param([object]$Value)

  if ($null -eq $Value) {
    return "null"
  }

  $number = [double]$Value
  if ($number -eq [math]::Truncate($number)) {
    return ([int64]$number).ToString()
  }

  return $number.ToString("0.####", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-FailureReason {
  param([object]$Reason)

  $suffix = "run$(if ([int]$Reason.count -eq 1) { '' } else { 's' })"
  if ([string]$Reason.reason -match "^expected_status_") {
    $suffix = "validated expected-failure run$(if ([int]$Reason.count -eq 1) { '' } else { 's' })"
  }

  return "``$($Reason.reason)`` with $($Reason.count) $suffix"
}

function Format-CategoryLine {
  param([object]$Category)

  $parts = @(
    "metric runs $($Category.reports_with_metrics)/$($Category.total_reports)",
    "MVP $($Category.mvp_passed_reports)/$($Category.reports_with_metrics)",
    "median $(Format-Number $Category.median_total_tokens)",
    "P90 $(Format-Number $Category.p90_total_tokens)"
  )

  if ([int]$Category.expected_failure_validated_reports -gt 0) {
    $parts += "expected-failure validated $($Category.expected_failure_validated_reports)"
  }

  return "- ``$($Category.category)``: $($parts -join '; ')."
}

function Format-ScopeLine {
  param([object]$Scope)

  $parts = @(
    "metric runs $($Scope.reports_with_metrics)/$($Scope.total_reports)",
    "MVP $($Scope.mvp_passed_reports)/$($Scope.reports_with_metrics)",
    "functional pass rate $(Format-Number $Scope.functional_pass_rate)",
    "median $(Format-Number $Scope.median_total_tokens)",
    "P90 $(Format-Number $Scope.p90_total_tokens)"
  )

  if ([int]$Scope.expected_failure_validated_reports -gt 0) {
    $parts += "expected-failure validated $($Scope.expected_failure_validated_reports)"
  }

  return "- ``$($Scope.scope)``: $($parts -join '; ')."
}

function Format-RepeatLine {
  param([object]$Repeat)

  $parts = @(
    "metric runs $($Repeat.reports_with_metrics)/$($Repeat.total_reports)",
    "MVP $($Repeat.mvp_passed_reports)/$($Repeat.reports_with_metrics)",
    "range $(Format-Number $Repeat.min_total_tokens)-$(Format-Number $Repeat.max_total_tokens)",
    "delta $(Format-Number $Repeat.range_total_tokens) tokens",
    "delta pct $(Format-Number $Repeat.range_total_tokens_pct_of_avg)%",
    "median $(Format-Number $Repeat.median_total_tokens)",
    "P90 $(Format-Number $Repeat.p90_total_tokens)"
  )

  return "- ``$($Repeat.repeat_group)``: $($parts -join '; ')."
}

$summaryJson = & (Join-Path $PSScriptRoot "summarize-token-results.ps1") -ResultsDir $ResultsDir -CasesPath $CasesPath
$summary = $summaryJson | ConvertFrom-Json

$nonBudgetReasons = @(
  $summary.failure_reason_counts |
    Where-Object { $_.reason -notmatch "budget_failed|missing_case_budget|missing_runner_metrics" }
)

$reasonLine = if ($nonBudgetReasons.Count -eq 0) {
  "none"
} elseif ($nonBudgetReasons.Count -eq 1) {
  Format-FailureReason $nonBudgetReasons[0]
} else {
  $formatted = @($nonBudgetReasons | ForEach-Object { Format-FailureReason $_ })
  (($formatted[0..($formatted.Count - 2)] -join ", ") + ", plus " + $formatted[-1])
}

$replacementLines = @(
  "Current summary snapshot:",
  "",
  "- reports with metrics: $($summary.reports_with_metrics) of $($summary.total_reports)",
  "- MVP-passed reports: $($summary.mvp_passed_reports)",
  "- expected-failure validated reports: $($summary.expected_failure_validated_reports)",
  "- median total tokens across metric runs: $(Format-Number $summary.median_total_tokens)",
  "- P90 total tokens across metric runs: $(Format-Number $summary.p90_total_tokens)",
  "- median total tokens for MVP-passed runs: $(Format-Number $summary.median_total_tokens_mvp_passed)",
  "- P90 total tokens for MVP-passed runs: $(Format-Number $summary.p90_total_tokens_mvp_passed)",
  "- main non-budget failure reasons: $reasonLine"
)

$categoryLines = @(
  "",
  "Current category snapshot:",
  ""
)

foreach ($category in @($summary.category_summary | Sort-Object -Property category)) {
  $categoryLines += Format-CategoryLine $category
}

$scopeLines = @(
  "",
  "Current scope snapshot:",
  ""
)

foreach ($scope in @($summary.scope_summary | Sort-Object -Property scope)) {
  $scopeLines += Format-ScopeLine $scope
}

$repeatLines = @(
  "",
  "Current repeat snapshot:",
  ""
)

if (@($summary.repeat_summary).Count -eq 0) {
  $repeatLines += "- none"
} else {
  foreach ($repeat in @($summary.repeat_summary | Sort-Object -Property repeat_group)) {
    $repeatLines += Format-RepeatLine $repeat
  }
}

$readme = Get-Content -Raw -LiteralPath $ReadmePath
$pattern = "(?s)Current summary snapshot:\r?\n\r?\n.*?(?=\r?\nCurrent escape-string-regexp token baseline:)"
$replacement = (($replacementLines + $categoryLines + $scopeLines + $repeatLines) -join "`r`n") + "`r`n"

if ($readme -notmatch $pattern) {
  throw "Could not find README summary snapshot block."
}

$updated = [regex]::Replace($readme, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)
Set-Content -LiteralPath $ReadmePath -Value $updated -NoNewline

[pscustomobject]@{
  readme = (Resolve-Path -LiteralPath $ReadmePath).Path
  total_reports = $summary.total_reports
  reports_with_metrics = $summary.reports_with_metrics
  mvp_passed_reports = $summary.mvp_passed_reports
  expected_failure_validated_reports = $summary.expected_failure_validated_reports
  category_count = @($summary.category_summary).Count
  scope_count = @($summary.scope_summary).Count
  repeat_group_count = @($summary.repeat_summary).Count
} | ConvertTo-Json
