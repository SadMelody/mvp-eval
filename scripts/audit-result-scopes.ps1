param(
  [string]$ResultsDir = ".\results",
  [string]$CasesPath = ".\cases.json",
  [string[]]$AllowedLegacyFailureReasons = @("total_token_budget_failed", "missing_runner_metrics")
)

$ErrorActionPreference = "Stop"

function Test-Subset {
  param(
    [string[]]$Values,
    [string[]]$Allowed
  )

  foreach ($value in $Values) {
    if ($Allowed -notcontains $value) {
      return $false
    }
  }

  return $true
}

$resolvedResults = Resolve-Path -LiteralPath $ResultsDir
$resolvedCases = Resolve-Path -LiteralPath $CasesPath
$summaryJson = & (Join-Path $PSScriptRoot "summarize-token-results.ps1") -ResultsDir $resolvedResults -CasesPath $resolvedCases
$summary = $summaryJson | ConvertFrom-Json
$runs = @($summary.runs)

$mvpRuns = @($runs | Where-Object { [string]$_.scope -eq "mvp" })
$expectedFailureRuns = @($runs | Where-Object { [string]$_.scope -eq "expected-failure" })
$legacyRuns = @($runs | Where-Object { [string]$_.scope -eq "legacy" })
$unknownScopeRuns = @($runs | Where-Object { @("mvp", "expected-failure", "legacy") -notcontains [string]$_.scope })

$mvpFailures = @(
  $mvpRuns |
    Where-Object {
      -not $_.has_metrics -or
      -not $_.mvp_passed -or
      @($_.failure_reasons).Count -gt 0
    } |
    Select-Object run_id, repo, status, has_metrics, mvp_passed, failure_reasons
)

$expectedFailureMismatches = @(
  $expectedFailureRuns |
    Where-Object { -not $_.expected_failure_validated } |
    Select-Object run_id, repo, status, expected_status, expected_status_matched, budget_passed, failure_reasons
)

$legacyUnexpectedFailures = @(
  $legacyRuns |
    Where-Object {
      $reasons = @($_.failure_reasons | ForEach-Object { [string]$_ })
      $reasons.Count -gt 0 -and -not (Test-Subset -Values $reasons -Allowed $AllowedLegacyFailureReasons)
    } |
    Select-Object run_id, repo, status, total_tokens, token_budget, failure_reasons
)

$checks = @(
  [pscustomobject]@{
    name = "mvp_scope_clean"
    passed = $mvpRuns.Count -gt 0 -and $mvpFailures.Count -eq 0
    summary = "$($mvpRuns.Count) MVP run(s), $($mvpFailures.Count) failure(s)."
  },
  [pscustomobject]@{
    name = "expected_failure_scope_validated"
    passed = $expectedFailureMismatches.Count -eq 0
    summary = "$($expectedFailureRuns.Count) expected-failure run(s), $($expectedFailureMismatches.Count) mismatch(es)."
  },
  [pscustomobject]@{
    name = "legacy_scope_explained"
    passed = $legacyUnexpectedFailures.Count -eq 0
    summary = "$($legacyRuns.Count) legacy run(s), $($legacyUnexpectedFailures.Count) unexpected failure reason set(s)."
  },
  [pscustomobject]@{
    name = "known_scopes_only"
    passed = $unknownScopeRuns.Count -eq 0
    summary = "$($unknownScopeRuns.Count) run(s) use an unknown scope."
  }
)

$failed = @($checks | Where-Object { -not $_.passed })
$status = if ($failed.Count -eq 0) { "passed" } else { "failed" }

[pscustomobject]@{
  status = $status
  results_dir = $resolvedResults.Path
  cases = $resolvedCases.Path
  totals = [pscustomobject]@{
    reports = $runs.Count
    mvp = $mvpRuns.Count
    expected_failure = $expectedFailureRuns.Count
    legacy = $legacyRuns.Count
    unknown_scope = $unknownScopeRuns.Count
  }
  allowed_legacy_failure_reasons = $AllowedLegacyFailureReasons
  checks = $checks
  failures = [pscustomobject]@{
    mvp = $mvpFailures
    expected_failure = $expectedFailureMismatches
    legacy = $legacyUnexpectedFailures
    unknown_scope = @($unknownScopeRuns | Select-Object run_id, repo, scope)
  }
} | ConvertTo-Json -Depth 8

if ($failed.Count -gt 0) {
  exit 1
}
