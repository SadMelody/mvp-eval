param(
  [string]$Scope = "mvp",

  [string]$ResultsDir = ".\results",

  [string]$CasesPath = ".\cases.json",

  [string]$OutputPath = ".\mvp-evidence.json",

  [string]$VerificationPath,

  [switch]$IncludeSmoke,

  [switch]$IncludeRealRepoSmoke
)

$ErrorActionPreference = "Stop"

function Invoke-JsonScript {
  param(
    [string]$Name,
    [string]$ScriptPath,
    [hashtable]$Parameters = @{}
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

  return [pscustomobject]@{
    name = $Name
    command = "$ScriptPath $(($Parameters.GetEnumerator() | ForEach-Object { if ($_.Value -is [bool] -and $_.Value) { "-$($_.Key)" } else { "-$($_.Key) $($_.Value)" } }) -join ' ')".Trim()
    exit_code = $exitCode
    parsed = $parsed
    parse_error = $parseError
    raw_output = if ($null -eq $parsed) { $text } else { $null }
  }
}

function Get-ByScope {
  param(
    [object[]]$Items,
    [string]$ScopeName
  )

  return @($Items | Where-Object { [string]$_.scope -eq $ScopeName } | Select-Object -First 1)
}

function Get-BooleanProperty {
  param(
    [object]$Object,
    [string]$Name,
    [bool]$Default = $false
  )

  if ($null -eq $Object) {
    return $Default
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $Default
  }

  return [bool]$property.Value
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedResults = Resolve-Path -LiteralPath $ResultsDir
$resolvedCases = Resolve-Path -LiteralPath $CasesPath
$target = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  [System.IO.Path]::GetFullPath($OutputPath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
}

$verifyParameters = @{ Scope = $Scope }
if ($VerificationPath) {
  $resolvedVerification = Resolve-Path -LiteralPath $VerificationPath
  $verificationParsed = $null
  $verificationParseError = $null

  try {
    $verificationParsed = Get-Content -Raw -LiteralPath $resolvedVerification.Path | ConvertFrom-Json
  } catch {
    $verificationParseError = $_.Exception.Message
  }

  $verification = [pscustomobject]@{
    name = "verification_suite"
    command = "Read existing verification: $($resolvedVerification.Path)"
    exit_code = if ($null -eq $verificationParseError) { 0 } else { 1 }
    parsed = $verificationParsed
    parse_error = $verificationParseError
    raw_output = $null
  }
} else {
  if ($IncludeSmoke) {
    $verifyParameters.IncludeSmoke = $true
  }
  if ($IncludeRealRepoSmoke) {
    $verifyParameters.IncludeRealRepoSmoke = $true
  }

  $verification = Invoke-JsonScript `
    -Name "verification_suite" `
    -ScriptPath (Join-Path $PSScriptRoot "verify-mvp-token-suite.ps1") `
    -Parameters $verifyParameters
}

$summary = Invoke-JsonScript `
  -Name "token_summary" `
  -ScriptPath (Join-Path $PSScriptRoot "summarize-token-results.ps1") `
  -Parameters @{ ResultsDir = $resolvedResults.Path; CasesPath = $resolvedCases.Path }

$passBar = Invoke-JsonScript `
  -Name "mvp_pass_bar" `
  -ScriptPath (Join-Path $PSScriptRoot "check-mvp-pass-bar.ps1") `
  -Parameters @{ ResultsDir = $resolvedResults.Path; CasesPath = $resolvedCases.Path; Scope = $Scope; NoExitOnFailure = $true }

$scopeAudit = Invoke-JsonScript `
  -Name "scope_audit" `
  -ScriptPath (Join-Path $PSScriptRoot "audit-result-scopes.ps1") `
  -Parameters @{ ResultsDir = $resolvedResults.Path; CasesPath = $resolvedCases.Path }

$coverage = Invoke-JsonScript `
  -Name "coverage_gap_audit" `
  -ScriptPath (Join-Path $PSScriptRoot "audit-coverage-gaps.ps1") `
  -Parameters @{ CasesPath = $resolvedCases.Path; Scope = $Scope }

$anomalies = Invoke-JsonScript `
  -Name "token_anomalies" `
  -ScriptPath (Join-Path $PSScriptRoot "analyze-token-anomalies.ps1") `
  -Parameters @{ ResultsDir = $resolvedResults.Path; CasesPath = $resolvedCases.Path; Scope = $Scope; Top = 5 }

$stability = Invoke-JsonScript `
  -Name "token_stability" `
  -ScriptPath (Join-Path $PSScriptRoot "export-token-stability.ps1") `
  -Parameters @{ ResultsDir = $resolvedResults.Path; CasesPath = $resolvedCases.Path; Scope = $Scope }

$summaryScope = if ($null -ne $summary.parsed) { Get-ByScope @($summary.parsed.scope_summary) $Scope } else { $null }
$failedChecks = @()
foreach ($check in @($verification, $summary, $passBar, $scopeAudit, $coverage, $anomalies, $stability)) {
  if ($check.exit_code -ne 0 -or $null -eq $check.parsed) {
    $failedChecks += $check.name
  }
}

if ($null -ne $verification.parsed -and [string]$verification.parsed.status -ne "passed") {
  $failedChecks += "verification_suite.status"
}

if ($null -ne $passBar.parsed -and [string]$passBar.parsed.status -ne "passed") {
  $failedChecks += "mvp_pass_bar.status"
}

if ($null -ne $scopeAudit.parsed -and [string]$scopeAudit.parsed.status -ne "passed") {
  $failedChecks += "scope_audit.status"
}

if ($null -ne $coverage.parsed -and [string]$coverage.parsed.status -ne "passed") {
  $failedChecks += "coverage_gap_audit.status"
}

if ($null -ne $anomalies.parsed -and [string]$anomalies.parsed.status -ne "passed") {
  $failedChecks += "token_anomalies.status"
}

if ($null -ne $stability.parsed -and [string]$stability.parsed.status -ne "passed") {
  $failedChecks += "token_stability.status"
}

$status = if ($failedChecks.Count -eq 0) { "passed" } else { "failed" }
$evidenceIncludeSmoke = if ($VerificationPath) {
  Get-BooleanProperty -Object $verification.parsed -Name "include_smoke" -Default $false
} else {
  [bool]$IncludeSmoke
}
$evidenceIncludeRealRepoSmoke = if ($VerificationPath) {
  Get-BooleanProperty -Object $verification.parsed -Name "include_realrepo_smoke" -Default $false
} else {
  [bool]$IncludeRealRepoSmoke
}

$evidence = [pscustomobject]@{
  status = $status
  generated_at = (Get-Date).ToString("o")
  scope = $Scope
  include_smoke = $evidenceIncludeSmoke
  include_realrepo_smoke = $evidenceIncludeRealRepoSmoke
  root = $root.Path
  results_dir = $resolvedResults.Path
  cases = $resolvedCases.Path
  output_path = $target
  headline = [pscustomobject]@{
    total_reports = if ($summaryScope) { $summaryScope.total_reports } else { $null }
    reports_with_metrics = if ($summaryScope) { $summaryScope.reports_with_metrics } else { $null }
    mvp_passed_reports = if ($summaryScope) { $summaryScope.mvp_passed_reports } else { $null }
    expected_failure_validated_reports = if ($summaryScope) { $summaryScope.expected_failure_validated_reports } else { $null }
    mvp_pass_rate = if ($summaryScope) { $summaryScope.mvp_pass_rate } else { $null }
    median_total_tokens_mvp_passed = if ($summaryScope) { $summaryScope.median_total_tokens_mvp_passed } else { $null }
    p90_total_tokens_mvp_passed = if ($summaryScope) { $summaryScope.p90_total_tokens_mvp_passed } else { $null }
    avg_tool_calls_mvp_passed = if ($summaryScope) { $summaryScope.avg_tool_calls_mvp_passed } else { $null }
    avg_duration_seconds_mvp_passed = if ($summaryScope) { $summaryScope.avg_duration_seconds_mvp_passed } else { $null }
  }
  verification = $verification.parsed
  pass_bar = $passBar.parsed
  scope_audit = $scopeAudit.parsed
  coverage = $coverage.parsed
  anomalies = $anomalies.parsed
  stability = $stability.parsed
  failed_checks = @($failedChecks | Select-Object -Unique)
  command_results = @(
    $verification,
    $summary,
    $passBar,
    $scopeAudit,
    $coverage,
    $anomalies,
    $stability
  ) | ForEach-Object {
    [pscustomobject]@{
      name = $_.name
      command = $_.command
      exit_code = $_.exit_code
      parsed = $null -ne $_.parsed
      parse_error = $_.parse_error
    }
  }
}

$targetDir = Split-Path -Parent $target
if (-not (Test-Path -LiteralPath $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir | Out-Null
}

$evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $target
$evidence | ConvertTo-Json -Depth 12

if ($failedChecks.Count -gt 0) {
  exit 1
}
