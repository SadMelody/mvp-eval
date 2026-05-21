param(
  [string]$ReadmePath = ".\README.md",
  [string]$ResultsDir = ".\results",
  [string]$CasesPath = ".\cases.json"
)

$ErrorActionPreference = "Stop"

function Add-Check {
  param(
    [string]$Name,
    [bool]$Passed,
    [string]$Summary
  )

  $script:checks += [pscustomobject]@{
    name = $Name
    passed = $Passed
    summary = $Summary
  }
}

function Count-ReadmePattern {
  param([string]$Pattern)

  return @(
    Select-String -LiteralPath $ReadmePath -Pattern $Pattern
  ).Count
}

$checks = @()
$resolvedReadme = Resolve-Path -LiteralPath $ReadmePath
$resolvedResults = Resolve-Path -LiteralPath $ResultsDir
$resolvedCases = Resolve-Path -LiteralPath $CasesPath

Get-Content -Raw -LiteralPath $resolvedCases | ConvertFrom-Json | Out-Null
Add-Check "cases_json_parseable" $true "Parsed $resolvedCases."

$summaryJson = & (Join-Path $PSScriptRoot "summarize-token-results.ps1") -ResultsDir $resolvedResults -CasesPath $resolvedCases
$summary = $summaryJson | ConvertFrom-Json

$updateJson = & (Join-Path $PSScriptRoot "update-readme-summary.ps1") -ReadmePath $resolvedReadme -ResultsDir $resolvedResults -CasesPath $resolvedCases
$update = $updateJson | ConvertFrom-Json

Add-Check "summary_has_reports" ([int]$summary.total_reports -gt 0) "Found $($summary.total_reports) result report(s)."
Add-Check "metrics_not_more_than_reports" ([int]$summary.reports_with_metrics -le [int]$summary.total_reports) "$($summary.reports_with_metrics) report(s) have metrics."
Add-Check "readme_summary_snapshot_unique" ((Count-ReadmePattern "^Current summary snapshot:$") -eq 1) "README has one summary snapshot block."
Add-Check "readme_category_snapshot_unique" ((Count-ReadmePattern "^Current category snapshot:$") -eq 1) "README has one category snapshot block."
Add-Check "readme_scope_snapshot_unique" ((Count-ReadmePattern "^Current scope snapshot:$") -eq 1) "README has one scope snapshot block."
Add-Check "readme_repeat_snapshot_unique" ((Count-ReadmePattern "^Current repeat snapshot:$") -eq 1) "README has one repeat snapshot block."
Add-Check "readme_baseline_anchor_unique" ((Count-ReadmePattern "^Current escape-string-regexp token baseline:$") -eq 1) "README has one baseline anchor."
Add-Check "update_matches_summary" (
  [int]$update.total_reports -eq [int]$summary.total_reports -and
  [int]$update.reports_with_metrics -eq [int]$summary.reports_with_metrics -and
  [int]$update.mvp_passed_reports -eq [int]$summary.mvp_passed_reports -and
  [int]$update.expected_failure_validated_reports -eq [int]$summary.expected_failure_validated_reports
) "README update output matches summary totals."

$failedChecks = @($checks | Where-Object { -not $_.passed })
$status = if ($failedChecks.Count -eq 0) { "passed" } else { "failed" }

[pscustomobject]@{
  status = $status
  readme = $resolvedReadme.Path
  results_dir = $resolvedResults.Path
  cases = $resolvedCases.Path
  total_reports = $summary.total_reports
  reports_with_metrics = $summary.reports_with_metrics
  mvp_passed_reports = $summary.mvp_passed_reports
  expected_failure_validated_reports = $summary.expected_failure_validated_reports
  category_count = @($summary.category_summary).Count
  scope_count = @($summary.scope_summary).Count
  repeat_group_count = @($summary.repeat_summary).Count
  checks = $checks
} | ConvertTo-Json -Depth 5

if ($failedChecks.Count -gt 0) {
  exit 1
}
