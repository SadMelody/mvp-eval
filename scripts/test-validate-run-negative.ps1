param(
  [switch]$KeepTemp
)

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

function Invoke-ValidatorExpectFailure {
  param(
    [string]$Name,
    [string]$RepoPath,
    [string]$ReportPath,
    [string]$RunId,
    [string]$Repo,
    [string]$CasesPath,
    [string[]]$ExpectedFailedChecks
  )

  $output = & (Join-Path $PSScriptRoot "validate-run.ps1") `
    -RepoPath $RepoPath `
    -ReportPath $ReportPath `
    -RunId $RunId `
    -Repo $Repo `
    -CasesPath $CasesPath `
    -RequireRunnerMetrics 2>&1

  $exitCode = $LASTEXITCODE
  $jsonText = ($output | Out-String).Trim()
  $validation = $jsonText | ConvertFrom-Json
  $failedNames = @($validation.results | Where-Object { -not $_.passed } | ForEach-Object { [string]$_.name })
  $missingExpected = @($ExpectedFailedChecks | Where-Object { $failedNames -notcontains $_ })

  return [pscustomobject]@{
    name = $Name
    passed = ($exitCode -ne 0 -and [bool]$validation.passed -eq $false -and $missingExpected.Count -eq 0)
    exit_code = $exitCode
    failed_checks = $failedNames
    missing_expected_checks = $missingExpected
  }
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$casesPath = Join-Path $root "cases.json"
$sourceReport = Join-Path $root "results\unit-string-trim-basic-token-single-001.json"
$sourceFixture = Join-Path $root "fixtures\unit-string-trim-basic"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mvp-validate-negative-" + [System.Guid]::NewGuid().ToString("N"))
$results = [System.Collections.Generic.List[object]]::new()

try {
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  $metricsMismatchReport = Join-Path $tempRoot "metrics-mismatch.json"
  $metricsMismatch = Get-Content -Raw -LiteralPath $sourceReport | ConvertFrom-Json
  $metricsMismatch.runner_metrics.total_tokens = [int64]$metricsMismatch.runner_metrics.total_tokens + 1
  $metricsMismatch | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $metricsMismatchReport

  $budgetOverrunReport = Join-Path $tempRoot "budget-overrun.json"
  $budgetOverrun = Get-Content -Raw -LiteralPath $sourceReport | ConvertFrom-Json
  $budgetOverrun.runner_metrics.input_tokens = 299000
  $budgetOverrun.runner_metrics.output_tokens = 1000
  $budgetOverrun.runner_metrics.total_tokens = 300000
  $budgetOverrun.runner_metrics.tool_calls = 40
  $budgetOverrun.runner_metrics.duration_seconds = 901
  $budgetOverrun | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $budgetOverrunReport

  $missingMetricsReport = Join-Path $tempRoot "missing-metrics.json"
  $missingMetrics = Get-Content -Raw -LiteralPath $sourceReport | ConvertFrom-Json
  $missingMetrics.runner_metrics.input_tokens = $null
  $missingMetrics | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $missingMetricsReport

  $extraTopLevelReport = Join-Path $tempRoot "extra-top-level.json"
  $extraTopLevel = Get-Content -Raw -LiteralPath $sourceReport | ConvertFrom-Json
  Add-Member -InputObject $extraTopLevel -NotePropertyName "unexpected" -NotePropertyValue $true
  $extraTopLevel | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $extraTopLevelReport

  $badCommandStatusReport = Join-Path $tempRoot "bad-command-status.json"
  $badCommandStatus = Get-Content -Raw -LiteralPath $sourceReport | ConvertFrom-Json
  @($badCommandStatus.agent_report.commands_run)[0].status = "ok"
  $badCommandStatus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $badCommandStatusReport

  $badRiskLevelReport = Join-Path $tempRoot "bad-risk-level.json"
  $badRiskLevel = Get-Content -Raw -LiteralPath $sourceReport | ConvertFrom-Json
  $badRiskLevel.agent_report.risk.level = "critical"
  $badRiskLevel | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $badRiskLevelReport

  $missingVerificationFieldReport = Join-Path $tempRoot "missing-verification-field.json"
  $missingVerificationField = Get-Content -Raw -LiteralPath $sourceReport | ConvertFrom-Json
  $missingVerificationField.agent_report.verification.PSObject.Properties.Remove("failed")
  $missingVerificationField | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $missingVerificationFieldReport

  $missingNpmCommandReport = Join-Path $tempRoot "missing-npm-command.json"
  $missingNpmCommand = Get-Content -Raw -LiteralPath $sourceReport | ConvertFrom-Json
  @($missingNpmCommand.agent_report.commands_run)[0].command = "npm install"
  $missingNpmCommand | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $missingNpmCommandReport

  $invalidJsonReport = Join-Path $tempRoot "invalid-json.json"
  Set-Content -LiteralPath $invalidJsonReport -Value "{ invalid json" -NoNewline

  $badEditRepo = Join-Path $tempRoot "bad-edit-repo"
  Copy-Item -LiteralPath $sourceFixture -Destination $badEditRepo -Recurse
  Push-Location $badEditRepo
  try {
    git init | Out-Null
    git config user.email "mvp-eval@example.local"
    git config user.name "MVP Eval Validator"
    git config core.autocrlf false
    git add .
    git commit -m "Create validator negative fixture" | Out-Null

    $indexPath = Join-Path $badEditRepo "index.js"
    $testPath = Join-Path $badEditRepo "test\basic.test.js"
    $indexSource = Get-Content -Raw -LiteralPath $indexPath
    $indexSource = $indexSource -replace "return value\.toLowerCase\(\);", "return value.trim().toLowerCase();"
    Set-Content -LiteralPath $indexPath -Value $indexSource -NoNewline

    $testSource = Get-Content -Raw -LiteralPath $testPath
    Set-Content -LiteralPath $testPath -Value ($testSource + "`n// validator negative self-test: this changed test file must be detected.`n") -NoNewline
  } finally {
    Pop-Location
  }

  $dependencyEditRepo = Join-Path $tempRoot "dependency-edit-repo"
  Copy-Item -LiteralPath $sourceFixture -Destination $dependencyEditRepo -Recurse
  Push-Location $dependencyEditRepo
  try {
    $indexPath = Join-Path $dependencyEditRepo "index.js"
    $indexSource = Get-Content -Raw -LiteralPath $indexPath
    $indexSource = $indexSource -replace "return value\.toLowerCase\(\);", "return value.trim().toLowerCase();"
    Set-Content -LiteralPath $indexPath -Value $indexSource -NoNewline

    $lockPath = Join-Path $dependencyEditRepo "package-lock.json"
    Set-Content -LiteralPath $lockPath -Value '{"lockfileVersion":3}' -NoNewline

    git init | Out-Null
    git config user.email "mvp-eval@example.local"
    git config user.name "MVP Eval Validator"
    git config core.autocrlf false
    git add .
    git commit -m "Create dependency negative fixture" | Out-Null

    Set-Content -LiteralPath $lockPath -Value '{"lockfileVersion":3,"packages":{}}' -NoNewline
  } finally {
    Pop-Location
  }

  $sourceCase = (Get-Content -Raw -LiteralPath $casesPath | ConvertFrom-Json | Where-Object { $_.id -eq "unit-string-trim-basic-token-single-001" } | Select-Object -First 1)
  $sourceRepo = [string]$sourceCase.path

  $budgetResultsDir = Join-Path $tempRoot "budget-results"
  New-Item -ItemType Directory -Path $budgetResultsDir | Out-Null
  Copy-Item -LiteralPath $budgetOverrunReport -Destination (Join-Path $budgetResultsDir "budget-overrun.json")

  $passBarOutput = & (Join-Path $PSScriptRoot "check-mvp-pass-bar.ps1") `
    -ResultsDir $budgetResultsDir `
    -CasesPath $casesPath `
    -Scope "mvp" `
    -NoExitOnFailure
  $passBar = ($passBarOutput | Out-String).Trim() | ConvertFrom-Json
  $passBarFailedGates = @($passBar.failed_gates | ForEach-Object { [string]$_ })

  $checks = @(
    Invoke-ValidatorExpectFailure `
      -Name "metrics_total_tokens_consistency" `
      -RepoPath $badEditRepo `
      -ReportPath $metricsMismatchReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("metrics.total_tokens.consistent", "report.changed_files.match_diff", "report.test_files_changed", "policy.test_files_changed")

    Invoke-ValidatorExpectFailure `
      -Name "budget_overrun_validator" `
      -RepoPath $sourceRepo `
      -ReportPath $budgetOverrunReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("budget.total_tokens", "budget.tool_calls", "budget.duration_seconds")

    Invoke-ValidatorExpectFailure `
      -Name "schema_extra_top_level" `
      -RepoPath $sourceRepo `
      -ReportPath $extraTopLevelReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("schema.top_level.exact")

    Invoke-ValidatorExpectFailure `
      -Name "schema_invalid_command_status" `
      -RepoPath $sourceRepo `
      -ReportPath $badCommandStatusReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("schema.commands_run.items")

    Invoke-ValidatorExpectFailure `
      -Name "schema_invalid_risk_level" `
      -RepoPath $sourceRepo `
      -ReportPath $badRiskLevelReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("schema.risk.level")

    Invoke-ValidatorExpectFailure `
      -Name "schema_missing_verification_field" `
      -RepoPath $sourceRepo `
      -ReportPath $missingVerificationFieldReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("schema.verification.exact", "schema.verification.failed")

    Invoke-ValidatorExpectFailure `
      -Name "missing_npm_test_command" `
      -RepoPath $sourceRepo `
      -ReportPath $missingNpmCommandReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("report.commands_run.npm_test_passed")

    Invoke-ValidatorExpectFailure `
      -Name "invalid_json_report" `
      -RepoPath $sourceRepo `
      -ReportPath $invalidJsonReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("json.parse")

    Invoke-ValidatorExpectFailure `
      -Name "metrics_required_presence" `
      -RepoPath $badEditRepo `
      -ReportPath $missingMetricsReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("metrics.input_tokens.present", "metrics.total_tokens.consistent", "report.changed_files.match_diff", "report.test_files_changed", "policy.test_files_changed")

    Invoke-ValidatorExpectFailure `
      -Name "test_file_edit_policy" `
      -RepoPath $badEditRepo `
      -ReportPath $sourceReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("report.changed_files.match_diff", "report.test_files_changed", "policy.test_files_changed")

    Invoke-ValidatorExpectFailure `
      -Name "dependency_file_edit_policy" `
      -RepoPath $dependencyEditRepo `
      -ReportPath $sourceReport `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @("report.changed_files.match_diff", "report.runtime_files_changed", "report.dependency_changed", "policy.dependency_change", "report.risk.score.basic")
  )

  foreach ($check in $checks) {
    Add-Result $results $check.name $check.passed ("failed_checks=[$($check.failed_checks -join ', ')]; missing_expected=[$($check.missing_expected_checks -join ', ')]")
  }

  $passBarBudgetPassed = (
    [string]$passBar.status -eq "failed" -and
    $passBarFailedGates -contains "median_token_budget_ratio" -and
    $passBarFailedGates -contains "p90_token_budget_ratio"
  )
  Add-Result $results "budget_overrun_pass_bar" $passBarBudgetPassed ("status=$($passBar.status); failed_gates=[$($passBarFailedGates -join ', ')]")

  $failed = @($results | Where-Object { -not $_.passed })
  $status = if ($failed.Count -eq 0) { "passed" } else { "failed" }

  [pscustomobject]@{
    status = $status
    temp_root = $tempRoot
    checks = $results
  } | ConvertTo-Json -Depth 8

  if ($failed.Count -gt 0) {
    exit 1
  }
} finally {
  if (-not $KeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -Recurse -Force -LiteralPath $tempRoot
  }
}
