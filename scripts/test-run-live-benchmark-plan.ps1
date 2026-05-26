param()

$ErrorActionPreference = "Stop"

function Assert-Condition {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$scriptPath = Join-Path $PSScriptRoot "run-live-benchmark.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mvp-live-benchmark-plan-" + [guid]::NewGuid().ToString("N"))
$checks = [System.Collections.Generic.List[string]]::new()

try {
  $singlePlan = (& $scriptPath `
    -CasesPath (Join-Path $root "cases.json") `
    -RunId "unit-bug-basic-token-single-001" `
    -Repeat 3 `
    -OutputRoot $tempRoot `
    -PlanOnly | Out-String).Trim() | ConvertFrom-Json

  Assert-Condition ($singlePlan.status -eq "passed" -and $singlePlan.mode -eq "plan") "Single-case plan did not report plan success."
  Assert-Condition ($singlePlan.planned_runs -eq 3 -and $singlePlan.selection.Count -eq 1) "Single-case plan selected the wrong runs."
  Assert-Condition (-not $singlePlan.token_spend_required) "Plan-only mode must not require token spend."
  Assert-Condition (-not (Test-Path -LiteralPath $tempRoot)) "Plan-only mode created output files."
  $checks.Add("single_case_plan") | Out-Null

  $repeatPlan = (& $scriptPath `
    -CasesPath (Join-Path $root "cases.json") `
    -RepeatGroup "unit-test-runtime-fix-token-single" `
    -Repeat 2 `
    -OutputRoot $tempRoot `
    -PlanOnly | Out-String).Trim() | ConvertFrom-Json

  Assert-Condition ($repeatPlan.planned_runs -eq 6 -and $repeatPlan.selection.Count -eq 3) "Repeat-group plan selected the wrong runs."
  $checks.Add("repeat_group_plan") | Out-Null

  $tokenGateBlocked = $false
  try {
    & $scriptPath `
      -CasesPath (Join-Path $root "cases.json") `
      -RunId "unit-bug-basic-token-single-001" `
      -OutputRoot $tempRoot | Out-Null
  } catch {
    $tokenGateBlocked = $_.Exception.Message -like "*ConfirmTokenSpend*"
  }

  Assert-Condition $tokenGateBlocked "Live mode was not blocked without explicit token-spend confirmation."
  Assert-Condition (-not (Test-Path -LiteralPath $tempRoot)) "Token-spend guard created output files."
  $checks.Add("token_spend_gate") | Out-Null

  $batchGateBlocked = $false
  try {
    & $scriptPath `
      -CasesPath (Join-Path $root "cases.json") `
      -RepeatGroup "unit-test-runtime-fix-token-single" `
      -Repeat 4 `
      -MaxRuns 10 `
      -PlanOnly | Out-Null
  } catch {
    $batchGateBlocked = $_.Exception.Message -like "*AllowLargeBatch*"
  }

  Assert-Condition $batchGateBlocked "Large batch mode was not blocked without explicit confirmation."
  $checks.Add("large_batch_gate") | Out-Null

  [pscustomobject]@{
    status = "passed"
    checks = $checks
    token_spending_run_executed = $false
  } | ConvertTo-Json -Depth 5
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
