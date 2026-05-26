param(
  [string]$Scope = "mvp",

  [switch]$IncludeSmoke,

  [switch]$IncludeRealRepoSmoke,

  [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Invoke-JsonCheck {
  param(
    [string]$Name,
    [string]$ScriptPath,
    [hashtable]$Parameters = @{},
    [string]$ExpectedStatus = "passed"
  )

  $output = & $ScriptPath @Parameters 2>&1
  $commandSucceeded = $?
  $exitCode = if ($commandSucceeded) { 0 } elseif ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 1 }
  $text = ($output | Out-String).Trim()
  $parsed = $null
  $parseError = $null

  try {
    $parsed = $text | ConvertFrom-Json
  } catch {
    $parseError = $_.Exception.Message
  }

  $actualStatus = if ($null -ne $parsed -and $null -ne $parsed.status) { [string]$parsed.status } else { $null }
  $passed = $exitCode -eq 0 -and $null -ne $parsed -and $actualStatus -eq $ExpectedStatus
  $summary = if ($null -ne $parseError) {
    "JSON parse failed: $parseError"
  } elseif ($null -ne $parsed -and $actualStatus -ne $ExpectedStatus -and $null -ne $parsed.checks) {
    $failedChildChecks = @($parsed.checks | Where-Object { -not $_.passed } | Select-Object -ExpandProperty name)
    $detail = if ($failedChildChecks.Count -gt 0) { " failed_checks=$($failedChildChecks -join ',')" } else { "" }
    $tempDetail = if ($null -ne $parsed.temp_root) { " temp_root=$($parsed.temp_root)" } else { "" }
    "status=$actualStatus$detail$tempDetail"
  } elseif ($null -ne $actualStatus) {
    "status=$actualStatus"
  } else {
    "JSON output did not include a status field."
  }

  [pscustomobject]@{
    name = $Name
    command = "$ScriptPath $(($Parameters.GetEnumerator() | ForEach-Object { if ($_.Value -is [bool] -and $_.Value) { "-$($_.Key)" } else { "-$($_.Key) $($_.Value)" } }) -join ' ')".Trim()
    passed = $passed
    exit_code = $exitCode
    summary = $summary
  }
}

function Test-PowerShellSyntax {
  param([string[]]$Files)

  $failed = @()
  foreach ($file in $Files) {
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
      $failed += [pscustomobject]@{
        file = $file
        errors = @($parseErrors | ForEach-Object { $_.Message })
      }
    }
  }

  [pscustomobject]@{
    name = "powershell_syntax"
    command = "Parser.ParseFile"
    passed = $failed.Count -eq 0
    exit_code = if ($failed.Count -eq 0) { 0 } else { 1 }
    summary = if ($failed.Count -eq 0) { "syntax ok" } else { "syntax errors in $($failed.Count) file(s)" }
    failed = $failed
  }
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$checks = [System.Collections.Generic.List[object]]::new()

$commands = @(
  [pscustomobject]@{
    name = "environment_setup_check"
    script = Join-Path $PSScriptRoot "setup.ps1"
    parameters = @{}
  },
  [pscustomobject]@{
    name = "prepare_case_repos"
    script = Join-Path $PSScriptRoot "prepare-case-repos.ps1"
    parameters = @{ Scope = $Scope; InstallDependencies = $true }
  },
  [pscustomobject]@{
    name = "negative_validator_self_test"
    script = Join-Path $PSScriptRoot "test-validate-run-negative.ps1"
    parameters = @{}
  },
  [pscustomobject]@{
    name = "schema_alignment_self_test"
    script = Join-Path $PSScriptRoot "test-validator-schema-alignment.ps1"
    parameters = @{}
  },
  [pscustomobject]@{
    name = "runner_metrics_extraction_self_test"
    script = Join-Path $PSScriptRoot "test-extract-runner-metrics.ps1"
    parameters = @{}
  },
  [pscustomobject]@{
    name = "live_benchmark_plan_self_test"
    script = Join-Path $PSScriptRoot "test-run-live-benchmark-plan.ps1"
    parameters = @{}
  },
  [pscustomobject]@{
    name = "refresh_token_summary"
    script = Join-Path $PSScriptRoot "refresh-token-summary.ps1"
    parameters = @{}
  },
  [pscustomobject]@{
    name = "result_scope_audit"
    script = Join-Path $PSScriptRoot "audit-result-scopes.ps1"
    parameters = @{}
  },
  [pscustomobject]@{
    name = "coverage_gap_audit"
    script = Join-Path $PSScriptRoot "audit-coverage-gaps.ps1"
    parameters = @{ Scope = $Scope }
  },
  [pscustomobject]@{
    name = "validate_all_scoped_results"
    script = Join-Path $PSScriptRoot "validate-all-results.ps1"
    parameters = @{ Scope = $Scope; NoExitOnFailure = $true }
  },
  [pscustomobject]@{
    name = "check_mvp_pass_bar"
    script = Join-Path $PSScriptRoot "check-mvp-pass-bar.ps1"
    parameters = @{ Scope = $Scope }
  },
  [pscustomobject]@{
    name = "analyze_token_anomalies"
    script = Join-Path $PSScriptRoot "analyze-token-anomalies.ps1"
    parameters = @{ Scope = $Scope; Top = 3 }
  },
  [pscustomobject]@{
    name = "export_token_stability"
    script = Join-Path $PSScriptRoot "export-token-stability.ps1"
    parameters = @{ Scope = $Scope }
  }
)

if ($IncludeSmoke) {
  $commands += [pscustomobject]@{
    name = "real_codex_case_smoke"
    script = Join-Path $PSScriptRoot "test-run-codex-case-smoke.ps1"
    parameters = @{}
  }
}

if ($IncludeRealRepoSmoke) {
  $commands += [pscustomobject]@{
    name = "real_codex_realrepo_smoke"
    script = Join-Path $PSScriptRoot "test-run-codex-realrepo-smoke.ps1"
    parameters = @{ KeepTempOnFailure = $true }
  }
}

foreach ($command in $commands) {
  $checks.Add((Invoke-JsonCheck -Name $command.name -ScriptPath $command.script -Parameters $command.parameters)) | Out-Null
}

$syntaxFiles = @(
  "validate-run.ps1",
  "extract-runner-metrics.ps1",
  "test-validate-run-negative.ps1",
  "test-validator-schema-alignment.ps1",
  "test-extract-runner-metrics.ps1",
  "run-live-benchmark.ps1",
  "test-run-live-benchmark-plan.ps1",
  "validate-all-results.ps1",
  "check-mvp-pass-bar.ps1",
  "analyze-token-anomalies.ps1",
  "audit-result-scopes.ps1",
  "audit-coverage-gaps.ps1",
  "export-mvp-evidence.ps1",
  "export-mvp-readiness.ps1",
  "export-token-stability.ps1",
  "setup.ps1",
  "prepare-case-repos.ps1",
  "run-codex-case.ps1",
  "test-run-codex-case-smoke.ps1",
  "test-run-codex-realrepo-smoke.ps1",
  "verify-mvp-token-suite.ps1"
) | ForEach-Object { Join-Path $PSScriptRoot $_ }
$checks.Add((Test-PowerShellSyntax -Files $syntaxFiles)) | Out-Null

$failed = @($checks | Where-Object { -not $_.passed })
$status = if ($failed.Count -eq 0) { "passed" } else { "failed" }

$report = [pscustomobject]@{
  status = $status
  scope = $Scope
  include_smoke = [bool]$IncludeSmoke
  include_realrepo_smoke = [bool]$IncludeRealRepoSmoke
  root = $root.Path
  checks = $checks
  failed_checks = @($failed | Select-Object -ExpandProperty name)
}

$json = $report | ConvertTo-Json -Depth 8
if ($OutputPath) {
  $target = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
  } else {
    [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
  }

  $targetDir = Split-Path -Parent $target
  if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
  }

  Set-Content -LiteralPath $target -Value $json
}

$json

if ($failed.Count -gt 0) {
  exit 1
}
