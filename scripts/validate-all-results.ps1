param(
  [string]$ResultsDir = ".\results",
  [string]$CasesPath = ".\cases.json",
  [string]$Scope = "mvp",
  [switch]$AllowMissingRunnerMetrics,
  [switch]$NoExitOnFailure
)

$ErrorActionPreference = "Stop"

function Test-ScopeMatch {
  param([object]$Case)

  if ($Scope -eq "all") {
    return $true
  }

  return $null -ne $Case -and [string]$Case.scope -eq $Scope
}

function Resolve-CasePath {
  param(
    [string]$Path,
    [string]$Root
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }

  return Join-Path -Path $Root -ChildPath $Path
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedResults = Resolve-Path -LiteralPath $ResultsDir
$resolvedCases = Resolve-Path -LiteralPath $CasesPath
$cases = @(Get-Content -Raw -LiteralPath $resolvedCases | ConvertFrom-Json)
$casesById = @{}
foreach ($case in $cases) {
  $casesById[[string]$case.id] = $case
}

$runResults = [System.Collections.Generic.List[object]]::new()

foreach ($file in Get-ChildItem -LiteralPath $resolvedResults -Filter *.json | Sort-Object Name) {
  try {
    $report = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
  } catch {
    $runResults.Add([pscustomobject]@{
      run_id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
      report = $file.FullName
      status = "failed"
      reason = "json_parse_failed"
      failed_checks = @("json.parse")
    }) | Out-Null
    continue
  }

  $runId = [string]$report.run_id
  $case = $casesById[$runId]
  if (-not (Test-ScopeMatch $case)) {
    $runResults.Add([pscustomobject]@{
      run_id = $runId
      report = $file.FullName
      status = "skipped"
      reason = "scope_mismatch"
      failed_checks = @()
    }) | Out-Null
    continue
  }

  if ($null -eq $case) {
    $runResults.Add([pscustomobject]@{
      run_id = $runId
      report = $file.FullName
      status = "skipped"
      reason = "case_not_found"
      failed_checks = @()
    }) | Out-Null
    continue
  }

  $repoPath = Resolve-CasePath -Path ([string]$case.path) -Root $root.Path
  if (-not (Test-Path -LiteralPath $repoPath)) {
    $runResults.Add([pscustomobject]@{
      run_id = $runId
      report = $file.FullName
      status = "skipped"
      reason = "repo_path_not_found"
      failed_checks = @()
    }) | Out-Null
    continue
  }

  $arguments = @{
    RepoPath = $repoPath
    ReportPath = $file.FullName
    RunId = $runId
    Repo = [string]$case.repo
    CasesPath = $resolvedCases.Path
  }
  if (-not $AllowMissingRunnerMetrics) {
    $arguments.RequireRunnerMetrics = $true
  }

  $output = & (Join-Path $PSScriptRoot "validate-run.ps1") @arguments 2>&1
  $exitCode = $LASTEXITCODE
  $jsonText = ($output | Out-String).Trim()

  try {
    $validation = $jsonText | ConvertFrom-Json
    $failedChecks = @($validation.results | Where-Object { -not $_.passed } | ForEach-Object { [string]$_.name })
    $passed = $exitCode -eq 0 -and [bool]$validation.passed
    $runResults.Add([pscustomobject]@{
      run_id = $runId
      report = $file.FullName
      status = if ($passed) { "passed" } else { "failed" }
      reason = if ($passed) { "" } else { "validator_failed" }
      failed_checks = $failedChecks
    }) | Out-Null
  } catch {
    $runResults.Add([pscustomobject]@{
      run_id = $runId
      report = $file.FullName
      status = "failed"
      reason = "validator_output_parse_failed"
      failed_checks = @("validator.output.parse")
    }) | Out-Null
  }
}

$validated = @($runResults | Where-Object { $_.status -eq "passed" -or $_.status -eq "failed" })
$passedRuns = @($runResults | Where-Object { $_.status -eq "passed" })
$failedRuns = @($runResults | Where-Object { $_.status -eq "failed" })
$skippedRuns = @($runResults | Where-Object { $_.status -eq "skipped" })
$status = if ($failedRuns.Count -eq 0 -and $validated.Count -gt 0) { "passed" } else { "failed" }

[pscustomobject]@{
  status = $status
  scope = $Scope
  results_dir = $resolvedResults.Path
  cases = $resolvedCases.Path
  total_reports_seen = @($runResults).Count
  validated_reports = $validated.Count
  passed_reports = $passedRuns.Count
  failed_reports = $failedRuns.Count
  skipped_reports = $skippedRuns.Count
  failed = @($failedRuns | Select-Object run_id, reason, failed_checks)
  skipped = @($skippedRuns | Group-Object reason | ForEach-Object {
    [pscustomobject]@{
      reason = $_.Name
      count = $_.Count
    }
  })
} | ConvertTo-Json -Depth 8

if ($failedRuns.Count -gt 0 -and -not $NoExitOnFailure) {
  exit 1
}
