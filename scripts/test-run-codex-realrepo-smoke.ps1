param(
  [string]$SourceRepoPath = "..\escape-string-regexp",

  [switch]$KeepTemp,

  [switch]$KeepTempOnFailure
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

function Resolve-ProjectPath {
  param(
    [string]$Path,
    [string]$Root
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$sourceRepo = Resolve-Path -LiteralPath (Resolve-ProjectPath -Path $SourceRepoPath -Root $root.Path)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mvp-codex-realrepo-smoke-" + [System.Guid]::NewGuid().ToString("N"))
$repoPath = Join-Path $tempRoot "repo"
$outputRoot = Join-Path $tempRoot "output"
$casesPath = Join-Path $tempRoot "cases.realrepo-smoke.json"
$archivePath = Join-Path $tempRoot "source.tar"
$installLog = Join-Path $tempRoot "npm-install.log"
$runId = "escape-string-regexp-realrepo-smoke-token-single-001"
$results = [System.Collections.Generic.List[object]]::new()
$status = "failed"

try {
  New-Item -ItemType Directory -Path $repoPath | Out-Null

  & git -C $sourceRepo.Path rev-parse --is-inside-work-tree 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "SourceRepoPath must be a git repository: $($sourceRepo.Path)"
  }

  & git -C $sourceRepo.Path archive --format=tar -o $archivePath HEAD
  if ($LASTEXITCODE -ne 0) {
    throw "git archive failed for $($sourceRepo.Path)"
  }

  & tar -xf $archivePath -C $repoPath
  if ($LASTEXITCODE -ne 0) {
    throw "tar extraction failed for $archivePath"
  }

  Push-Location $repoPath
  try {
    & npm install --ignore-scripts --no-audit --no-fund *> $installLog
    if ($LASTEXITCODE -ne 0) {
      throw "npm install failed; log=$installLog"
    }

    & git -c core.autocrlf=false init 2>$null | Out-Null
    & git -c core.autocrlf=false add . 2>$null | Out-Null
    & git -c core.autocrlf=false -c user.email="mvp-realrepo-smoke@example.invalid" -c user.name="MVP RealRepo Smoke" commit -m "Baseline real repo smoke fixture" 2>$null | Out-Null
  } finally {
    Pop-Location
  }

  @(
    [pscustomobject]@{
      id = $runId
      repo = "escape-string-regexp"
      path = $repoPath
      category = "typecheck-tooling"
      scope = "mvp"
      scenario = "real-package-typecheck-tsd-ambient-types-live-smoke"
      task = "在不改变运行时行为的前提下，让 npm test 通过。"
      token_budget = [pscustomobject]@{
        total_tokens = 500000
        tool_calls = 35
        duration_seconds = 1200
      }
      expected = [pscustomobject]@{
        allow_runtime_change = $false
        allow_test_deletion = $false
        required_commands = @("npm test")
      }
    }
  ) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $casesPath

  $smokeJson = & (Join-Path $PSScriptRoot "run-codex-case.ps1") `
    -CasesPath $casesPath `
    -RunId $runId `
    -TemplatePath (Join-Path $root "agent-task-template.md") `
    -OutputRoot $outputRoot `
    -Validate
  $smoke = $smokeJson | ConvertFrom-Json

  $resultExists = Test-Path -LiteralPath $smoke.result_path
  $eventExists = Test-Path -LiteralPath $smoke.event_path
  $report = if ($resultExists) { Get-Content -Raw -LiteralPath $smoke.result_path | ConvertFrom-Json } else { $null }
  $metricsConsistent = $false
  if ($null -ne $report -and $null -ne $report.runner_metrics) {
    $metricsConsistent = [int64]$report.runner_metrics.total_tokens -eq ([int64]$report.runner_metrics.input_tokens + [int64]$report.runner_metrics.output_tokens)
  }

  Add-Result $results "smoke.result_written" $resultExists "result_path=$($smoke.result_path)"
  Add-Result $results "smoke.event_written" $eventExists "event_path=$($smoke.event_path)"
  Add-Result $results "smoke.validation_passed" ([bool]$smoke.validation_passed) "validation_passed=$($smoke.validation_passed)"
  Add-Result $results "smoke.metrics_present" ($null -ne $report -and $null -ne $report.runner_metrics -and $null -ne $report.runner_metrics.total_tokens) "total_tokens=$($report.runner_metrics.total_tokens)"
  Add-Result $results "smoke.metrics_consistent" $metricsConsistent "input=$($report.runner_metrics.input_tokens), output=$($report.runner_metrics.output_tokens), total=$($report.runner_metrics.total_tokens)"
  Add-Result $results "smoke.agent_passed" ($null -ne $report -and [string]$report.agent_report.status -eq "passed") "status=$($report.agent_report.status)"
  Add-Result $results "smoke.no_runtime_change" ($null -ne $report -and -not [bool]$report.agent_report.runtime_files_changed) "runtime_files_changed=$($report.agent_report.runtime_files_changed)"
  Add-Result $results "smoke.no_test_change" ($null -ne $report -and -not [bool]$report.agent_report.test_files_changed) "test_files_changed=$($report.agent_report.test_files_changed)"

  $failed = @($results | Where-Object { -not $_.passed })
  $status = if ($failed.Count -eq 0) { "passed" } else { "failed" }

  [pscustomobject]@{
    status = $status
    temp_root = $tempRoot
    source_repo = $sourceRepo.Path
    run = $smoke
    checks = $results
  } | ConvertTo-Json -Depth 8

  if ($failed.Count -gt 0) {
    exit 1
  }
} finally {
  $shouldKeepTemp = $KeepTemp -or ($KeepTempOnFailure -and $status -ne "passed")
  if (-not $shouldKeepTemp -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -Recurse -Force -LiteralPath $tempRoot
  }
}
