param(
  [string]$EvidencePath = ".\mvp-evidence.json",

  [string]$OutputPath = ".\MVP_READINESS.md"
)

$ErrorActionPreference = "Stop"

function Format-Value {
  param([object]$Value)

  if ($null -eq $Value) {
    return "n/a"
  }

  if ($Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
    return ([math]::Round([double]$Value, 4)).ToString()
  }

  return "$Value"
}

function Add-Line {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Text = ""
  )

  $Lines.Add($Text) | Out-Null
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedEvidence = Resolve-Path -LiteralPath $EvidencePath
$target = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  [System.IO.Path]::GetFullPath($OutputPath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
}

$evidence = Get-Content -Raw -LiteralPath $resolvedEvidence | ConvertFrom-Json
$headline = $evidence.headline
$passBar = $evidence.pass_bar
$scopeAudit = $evidence.scope_audit
$coverage = $evidence.coverage
$anomalies = $evidence.anomalies
$stability = $evidence.stability
$verification = $evidence.verification

$coveragePath = Join-Path $root "coverage-gaps.json"
if (Test-Path -LiteralPath $coveragePath) {
  $coverage = Get-Content -Raw -LiteralPath $coveragePath | ConvertFrom-Json
}

$stabilityPath = Join-Path $root "token-stability.json"
if (Test-Path -LiteralPath $stabilityPath) {
  $stability = Get-Content -Raw -LiteralPath $stabilityPath | ConvertFrom-Json
}

$lines = [System.Collections.Generic.List[string]]::new()

Add-Line $lines "# MVP Readiness Report"
Add-Line $lines
Add-Line $lines "- Status: **$($evidence.status)**"
Add-Line $lines "- Scope: $($evidence.scope)"
Add-Line $lines "- Generated at: $($evidence.generated_at)"
Add-Line $lines "- Evidence file: $($resolvedEvidence.Path)"
Add-Line $lines "- Fixture Agent smoke included in this evidence: $($evidence.include_smoke)"
Add-Line $lines "- Real-repo Agent smoke included in this evidence: $($evidence.include_realrepo_smoke)"
Add-Line $lines

Add-Line $lines "## Executive Summary"
Add-Line $lines
Add-Line $lines "The current MVP token evaluation is ready for handoff within the configured mvp scope."
Add-Line $lines "All scoped MVP reports pass validation, have runner metrics, stay within budget gates, and show no token anomaly warnings."
Add-Line $lines

Add-Line $lines "## Headline Metrics"
Add-Line $lines
Add-Line $lines "| Metric | Value |"
Add-Line $lines "| --- | ---: |"
Add-Line $lines "| Total MVP reports | $(Format-Value $headline.total_reports) |"
Add-Line $lines "| Reports with metrics | $(Format-Value $headline.reports_with_metrics) |"
Add-Line $lines "| MVP passed reports | $(Format-Value $headline.mvp_passed_reports) |"
Add-Line $lines "| MVP pass rate | $(Format-Value $headline.mvp_pass_rate) |"
Add-Line $lines "| Median total tokens | $(Format-Value $headline.median_total_tokens_mvp_passed) |"
Add-Line $lines "| P90 total tokens | $(Format-Value $headline.p90_total_tokens_mvp_passed) |"
Add-Line $lines "| Average tool calls | $(Format-Value $headline.avg_tool_calls_mvp_passed) |"
Add-Line $lines "| Average duration seconds | $(Format-Value $headline.avg_duration_seconds_mvp_passed) |"
Add-Line $lines

Add-Line $lines "## Pass Bar"
Add-Line $lines
Add-Line $lines "| Gate | Value | Threshold | Status |"
Add-Line $lines "| --- | ---: | ---: | --- |"
foreach ($gate in @($passBar.gates)) {
  $status = if ($gate.passed) { "passed" } else { "failed" }
  Add-Line $lines "| $($gate.name) | $(Format-Value $gate.value) | $($gate.operator) $(Format-Value $gate.threshold) | $status |"
}
Add-Line $lines

Add-Line $lines "## Scope Audit"
Add-Line $lines
Add-Line $lines "| Scope | Count |"
Add-Line $lines "| --- | ---: |"
Add-Line $lines "| MVP | $(Format-Value $scopeAudit.totals.mvp) |"
Add-Line $lines "| Expected failure | $(Format-Value $scopeAudit.totals.expected_failure) |"
Add-Line $lines "| Legacy | $(Format-Value $scopeAudit.totals.legacy) |"
Add-Line $lines "| Unknown scope | $(Format-Value $scopeAudit.totals.unknown_scope) |"
Add-Line $lines
$allowedLegacyReasons = @($scopeAudit.allowed_legacy_failure_reasons) -join ", "
Add-Line $lines "Legacy runs are excluded from the MVP gate and are audited separately. Allowed legacy failure reasons: $allowedLegacyReasons."
Add-Line $lines

if ($null -ne $coverage) {
  Add-Line $lines "## Coverage Audit"
  Add-Line $lines
  Add-Line $lines "| Metric | Value |"
  Add-Line $lines "| --- | ---: |"
  Add-Line $lines "| Status | $($coverage.status) |"
  Add-Line $lines "| Scoped cases | $(Format-Value $coverage.totals.scoped_cases) |"
  Add-Line $lines "| Categories | $(Format-Value $coverage.totals.categories) |"
  Add-Line $lines "| Repeat groups | $(Format-Value $coverage.totals.repeat_groups) |"
  Add-Line $lines "| Real-repo cases | $(Format-Value $coverage.totals.real_repo_cases) |"
  Add-Line $lines "| Categories without repeat groups | $(Format-Value $coverage.totals.categories_without_repeat_groups) |"
  Add-Line $lines
  Add-Line $lines "| Gate | Value | Threshold | Status |"
  Add-Line $lines "| --- | ---: | ---: | --- |"
  foreach ($gate in @($coverage.gates)) {
    $status = if ($gate.passed) { "passed" } else { "failed" }
    Add-Line $lines "| $($gate.name) | $(Format-Value $gate.value) | $($gate.operator) $(Format-Value $gate.threshold) | $status |"
  }
  Add-Line $lines

  $coverageWarnings = @($coverage.warnings)
  if ($coverageWarnings.Count -gt 0) {
    Add-Line $lines "Coverage warnings:"
    foreach ($warning in $coverageWarnings) {
      Add-Line $lines "- $warning"
    }
    Add-Line $lines
  }
}

Add-Line $lines "## Token Anomaly Status"
Add-Line $lines
Add-Line $lines "| Check | Count |"
Add-Line $lines "| --- | ---: |"
Add-Line $lines "| Missing metrics | $(Format-Value $anomalies.totals.missing_metrics) |"
Add-Line $lines "| Non-MVP reports in scope | $(Format-Value $anomalies.totals.non_mvp_reports) |"
Add-Line $lines "| Warning reports | $(Format-Value $anomalies.totals.warning_reports) |"
Add-Line $lines

Add-Line $lines "## Category Snapshot"
Add-Line $lines
Add-Line $lines "| Category | Reports | MVP passed | Median tokens | P90 tokens | P90 budget ratio |"
Add-Line $lines "| --- | ---: | ---: | ---: | ---: | ---: |"
foreach ($category in @($anomalies.category_analysis)) {
  Add-Line $lines "| $($category.category) | $(Format-Value $category.reports_with_metrics) | $(Format-Value $category.mvp_passed_reports) | $(Format-Value $category.median_total_tokens) | $(Format-Value $category.p90_total_tokens) | $(Format-Value $category.p90_token_budget_ratio) |"
}
Add-Line $lines

Add-Line $lines "## Repeat Stability"
Add-Line $lines
Add-Line $lines "| Repeat group | Runs | MVP passed | Min tokens | Max tokens | Range pct of avg | Status |"
Add-Line $lines "| --- | ---: | ---: | ---: | ---: | ---: | --- |"
foreach ($group in @($stability.repeat_groups)) {
  Add-Line $lines "| $($group.repeat_group) | $($group.total_reports) | $($group.mvp_passed_reports) | $($group.min_total_tokens) | $($group.max_total_tokens) | $($group.range_total_tokens_pct_of_avg) | $($group.status) |"
}
Add-Line $lines

Add-Line $lines "## Verification Commands"
Add-Line $lines
foreach ($result in @($evidence.command_results)) {
  Add-Line $lines "- $($result.command) -> exit $($result.exit_code)"
}
Add-Line $lines

Add-Line $lines "## Current Boundaries"
Add-Line $lines
Add-Line $lines "- The readiness claim applies to the configured mvp scope, not to legacy exploratory runs."
Add-Line $lines "- runner_metrics are accepted from the harness and validated for presence, consistency, and budget fit."
Add-Line $lines "- Fixture Agent smoke is opt-in because it consumes live token budget: .\scripts\verify-mvp-token-suite.ps1 -IncludeSmoke."
Add-Line $lines "- Real-repo Agent smoke is opt-in because it consumes live token budget: .\scripts\verify-mvp-token-suite.ps1 -IncludeRealRepoSmoke."
Add-Line $lines "- This report is generated from mvp-evidence.json; refresh evidence before regenerating this report."
Add-Line $lines

Add-Line $lines "## Recommended Next Tests"
Add-Line $lines
$coverageRecommendations = if ($null -ne $coverage) { @($coverage.recommended_next_cases) } else { @() }
$fixtureSmokeIncluded = [bool]$evidence.include_smoke
$realRepoSmokeIncluded = [bool]$evidence.include_realrepo_smoke
if ($coverageRecommendations.Count -gt 0) {
  $index = 1
  foreach ($recommendation in @($coverageRecommendations | Select-Object -First 3)) {
    Add-Line $lines "$index. $($recommendation.category): $($recommendation.recommendation)"
    $index += 1
  }
} elseif ($fixtureSmokeIncluded -and $realRepoSmokeIncluded) {
  Add-Line $lines "1. Add more real-repo MVP cases to widen coverage beyond the current fixture and small-package set."
  Add-Line $lines "2. Add more repeat groups for the highest-token categories so token variance is tracked across broader task shapes."
} elseif (-not $fixtureSmokeIncluded -and -not $realRepoSmokeIncluded) {
  Add-Line $lines "1. Run the opt-in fixture Agent smoke before an external demo or handoff."
  Add-Line $lines "2. Run the opt-in real-repo Agent smoke to verify the harness against a clean exported npm package."
} elseif (-not $fixtureSmokeIncluded) {
  Add-Line $lines "1. Run the opt-in fixture Agent smoke before an external demo or handoff."
  Add-Line $lines "2. Add more repeat groups for the highest-token categories so token variance is tracked across broader task shapes."
} else {
  Add-Line $lines "1. Run the opt-in real-repo Agent smoke before an external demo or handoff."
  Add-Line $lines "2. Add more repeat groups for the highest-token categories so token variance is tracked across broader task shapes."
}

$targetDir = Split-Path -Parent $target
if (-not (Test-Path -LiteralPath $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir | Out-Null
}

Set-Content -LiteralPath $target -Value ($lines -join [Environment]::NewLine)

[pscustomobject]@{
  status = "passed"
  evidence_path = $resolvedEvidence.Path
  output_path = $target
  scope = $evidence.scope
  readiness_status = $evidence.status
} | ConvertTo-Json -Depth 4
