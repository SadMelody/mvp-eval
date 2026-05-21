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

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mvp-codex-smoke-" + [System.Guid]::NewGuid().ToString("N"))
$repoPath = Join-Path $tempRoot "repo"
$outputRoot = Join-Path $tempRoot "output"
$casesPath = Join-Path $tempRoot "cases.smoke.json"
$runId = "unit-string-trim-smoke-token-single-001"
$results = [System.Collections.Generic.List[object]]::new()

try {
  New-Item -ItemType Directory -Path $repoPath | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $root "fixtures\unit-string-trim-basic") |
    Copy-Item -Recurse -Destination $repoPath

  & git -C $repoPath -c core.autocrlf=false init 2>$null | Out-Null
  & git -C $repoPath -c core.autocrlf=false add . 2>$null | Out-Null
  & git -C $repoPath -c core.autocrlf=false -c user.email="mvp-smoke@example.invalid" -c user.name="MVP Smoke" commit -m "Baseline fixture" 2>$null | Out-Null

  @(
    [pscustomobject]@{
      id = $runId
      repo = "unit-string-trim-basic"
      path = $repoPath
      category = "smoke"
      scope = "mvp"
      task = "让 npm test 通过；允许最小范围运行时代码修复，但不要修改测试或依赖。"
      token_budget = [pscustomobject]@{
        total_tokens = 500000
        tool_calls = 35
        duration_seconds = 900
      }
      expected = [pscustomobject]@{
        allow_runtime_change = $true
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

  Add-Result $results "smoke.result_written" $resultExists "result_path=$($smoke.result_path)"
  Add-Result $results "smoke.event_written" $eventExists "event_path=$($smoke.event_path)"
  Add-Result $results "smoke.validation_passed" ([bool]$smoke.validation_passed) "validation_passed=$($smoke.validation_passed)"
  Add-Result $results "smoke.metrics_present" ($null -ne $report -and $null -ne $report.runner_metrics -and $null -ne $report.runner_metrics.total_tokens) "total_tokens=$($report.runner_metrics.total_tokens)"
  Add-Result $results "smoke.metrics_consistent" ($null -ne $report -and [int64]$report.runner_metrics.total_tokens -eq ([int64]$report.runner_metrics.input_tokens + [int64]$report.runner_metrics.output_tokens)) "input=$($report.runner_metrics.input_tokens), output=$($report.runner_metrics.output_tokens), total=$($report.runner_metrics.total_tokens)"

  $failed = @($results | Where-Object { -not $_.passed })
  $status = if ($failed.Count -eq 0) { "passed" } else { "failed" }

  [pscustomobject]@{
    status = $status
    temp_root = $tempRoot
    run = $smoke
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
