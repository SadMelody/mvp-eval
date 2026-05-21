param(
  [string]$ResultsDir = ".\results",
  [string]$CasesPath = ".\cases.json",
  [string]$Scope = "mvp",
  [switch]$NoExitOnFailure
)

$ErrorActionPreference = "Stop"

function Get-Percentile {
  param(
    [double[]]$Values,
    [double]$Percentile
  )

  $sorted = @($Values | Sort-Object)
  if ($sorted.Count -eq 0) {
    return $null
  }

  if ($sorted.Count -eq 1) {
    return [math]::Round($sorted[0], 4)
  }

  $rank = ($Percentile / 100) * ($sorted.Count - 1)
  $lower = [math]::Floor($rank)
  $upper = [math]::Ceiling($rank)

  if ($lower -eq $upper) {
    return [math]::Round($sorted[$lower], 4)
  }

  $weight = $rank - $lower
  return [math]::Round(($sorted[$lower] * (1 - $weight)) + ($sorted[$upper] * $weight), 4)
}

function Add-Gate {
  param(
    [string]$Name,
    [double]$Value,
    [string]$Operator,
    [double]$Threshold,
    [bool]$Passed,
    [string]$Summary
  )

  $script:gates += [pscustomobject]@{
    name = $Name
    value = $Value
    operator = $Operator
    threshold = $Threshold
    passed = $Passed
    summary = $Summary
  }
}

function Test-MinimalSchema {
  param([object]$Report)

  if ($null -eq $Report.run_id -or $null -eq $Report.repo -or $null -eq $Report.task) {
    return $false
  }

  if ($null -eq $Report.agent_report -or $null -eq $Report.runner_metrics) {
    return $false
  }

  foreach ($field in @("status", "changed_files", "runtime_files_changed", "test_files_changed", "dependency_changed", "commands_run", "verification", "risk")) {
    if ($null -eq $Report.agent_report.$field) {
      return $false
    }
  }

  return $true
}

function Test-RequiredCommandsRan {
  param(
    [object]$Report,
    [object]$Case
  )

  $required = @("npm test")
  if ($null -ne $Case -and $null -ne $Case.expected -and $null -ne $Case.expected.required_commands) {
    $required = @($Case.expected.required_commands)
  }

  $commands = @($Report.agent_report.commands_run | ForEach-Object { [string]$_.command })
  foreach ($command in $required) {
    if (-not @($commands | Where-Object { $_ -eq $command -or $_ -like "*$command*" }).Count) {
      return $false
    }
  }

  return $true
}

function Test-NoForbiddenEdit {
  param(
    [object]$Report,
    [object]$Case
  )

  $expected = if ($null -ne $Case) { $Case.expected } else { $null }
  $allowRuntimeChange = $null -ne $expected -and $expected.allow_runtime_change -eq $true
  $allowDependencyChange = $null -ne $expected -and $expected.dependency_changed -eq $true

  if ($Report.agent_report.runtime_files_changed -eq $true -and -not $allowRuntimeChange) {
    return $false
  }

  if ($Report.agent_report.test_files_changed -eq $true) {
    return $false
  }

  if ($Report.agent_report.dependency_changed -eq $true -and -not $allowDependencyChange) {
    return $false
  }

  return $true
}

function Test-ScopeMatch {
  param([object]$Case)

  if ($Scope -eq "all") {
    return $true
  }

  return $null -ne $Case -and [string]$Case.scope -eq $Scope
}

$resolvedResults = Resolve-Path -LiteralPath $ResultsDir
$resolvedCases = Resolve-Path -LiteralPath $CasesPath
$cases = @(Get-Content -Raw -LiteralPath $resolvedCases | ConvertFrom-Json)
$casesById = @{}
foreach ($case in $cases) {
  $casesById[$case.id] = $case
}

$summaryJson = & (Join-Path $PSScriptRoot "summarize-token-results.ps1") -ResultsDir $resolvedResults -CasesPath $resolvedCases
$summary = $summaryJson | ConvertFrom-Json

$reports = @()
$schemaPassed = 0
$forbiddenClean = 0
$verificationComplete = 0

foreach ($file in Get-ChildItem -LiteralPath $resolvedResults -Filter *.json) {
  $report = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
  $case = $casesById[$report.run_id]
  if (-not (Test-ScopeMatch $case)) {
    continue
  }

  $schemaOk = Test-MinimalSchema $report

  if ($schemaOk) {
    $schemaPassed += 1
  }

  if ($schemaOk -and (Test-NoForbiddenEdit $report $case)) {
    $forbiddenClean += 1
  }

  if ($schemaOk -and (Test-RequiredCommandsRan $report $case)) {
    $verificationComplete += 1
  }

  $reports += [pscustomobject]@{
    run_id = $report.run_id
    schema_passed = $schemaOk
    no_forbidden_edit = if ($schemaOk) { Test-NoForbiddenEdit $report $case } else { $false }
    required_commands_ran = if ($schemaOk) { Test-RequiredCommandsRan $report $case } else { $false }
  }
}

$filteredRuns = @(
  $summary.runs |
    Where-Object { $Scope -eq "all" -or [string]$_.scope -eq $Scope }
)
$metricRuns = @($filteredRuns | Where-Object { $_.has_metrics })
$budgetedMetricRuns = @($metricRuns | Where-Object { $null -ne $_.token_budget -and [double]$_.token_budget -gt 0 })
$budgetRatios = @(
  $budgetedMetricRuns |
    ForEach-Object { [double]$_.total_tokens / [double]$_.token_budget }
)

$reportCount = @($reports).Count
$metricsCaptureRate = if ($reportCount -eq 0) { 0 } else { [math]::Round($metricRuns.Count / $reportCount, 4) }
$jsonSchemaComplianceRate = if ($reportCount -eq 0) { 0 } else { [math]::Round($schemaPassed / $reportCount, 4) }
$passedMetricRuns = @($metricRuns | Where-Object { $_.status -eq "passed" })
$mvpPassedRuns = @($metricRuns | Where-Object { $_.mvp_passed })
$expectedFailureValidatedRuns = @($metricRuns | Where-Object { $_.expected_failure_validated })
$functionalPassRate = if ($metricRuns.Count -eq 0) { 0 } else { [math]::Round($passedMetricRuns.Count / $metricRuns.Count, 4) }
$medianBudgetRatio = Get-Percentile $budgetRatios 50
$p90BudgetRatio = Get-Percentile $budgetRatios 90
$noForbiddenEditRate = if ($reportCount -eq 0) { 0 } else { [math]::Round($forbiddenClean / $reportCount, 4) }
$fullVerificationRate = if ($reportCount -eq 0) { 0 } else { [math]::Round($verificationComplete / $reportCount, 4) }

$gates = @()
Add-Gate "metrics_capture_rate" $metricsCaptureRate ">=" 0.95 ($metricsCaptureRate -ge 0.95) "Runner metrics present on $($metricRuns.Count)/$reportCount scoped reports."
Add-Gate "json_schema_compliance_rate" $jsonSchemaComplianceRate ">=" 0.95 ($jsonSchemaComplianceRate -ge 0.95) "Minimal report schema present on $schemaPassed/$reportCount reports."
Add-Gate "functional_pass_rate" $functionalPassRate ">=" 0.70 ($functionalPassRate -ge 0.70) "$($passedMetricRuns.Count)/$($metricRuns.Count) scoped metric reports have agent_report.status = passed."
Add-Gate "median_token_budget_ratio" $medianBudgetRatio "<=" 1.00 ($null -ne $medianBudgetRatio -and $medianBudgetRatio -le 1) "Median total_tokens/token_budget across budgeted metric runs."
Add-Gate "p90_token_budget_ratio" $p90BudgetRatio "<=" 1.00 ($null -ne $p90BudgetRatio -and $p90BudgetRatio -le 1) "P90 total_tokens/token_budget across budgeted metric runs."
Add-Gate "no_forbidden_edit_rate" $noForbiddenEditRate ">=" 0.90 ($noForbiddenEditRate -ge 0.90) "Reported edit flags comply with case expectations on $forbiddenClean/$reportCount reports."
Add-Gate "full_verification_execution_rate" $fullVerificationRate ">=" 0.95 ($fullVerificationRate -ge 0.95) "Required commands are reported on $verificationComplete/$reportCount reports."

$failedGates = @($gates | Where-Object { -not $_.passed })
$status = if ($failedGates.Count -eq 0) { "passed" } else { "failed" }

[pscustomobject]@{
  status = $status
  scope = $Scope
  results_dir = $resolvedResults.Path
  cases = $resolvedCases.Path
  total_reports = $reportCount
  reports_with_metrics = $metricRuns.Count
  mvp_passed_reports = $mvpPassedRuns.Count
  expected_failure_validated_reports = $expectedFailureValidatedRuns.Count
  gates = $gates
  failed_gates = @($failedGates | Select-Object -ExpandProperty name)
} | ConvertTo-Json -Depth 6

if ($failedGates.Count -gt 0 -and -not $NoExitOnFailure) {
  exit 1
}
