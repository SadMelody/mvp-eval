param(
  [string]$CasesPath = ".\cases.json",

  [string]$Scope = "mvp",

  [string[]]$RunId,

  [string]$RepeatGroup,

  [ValidateRange(1, 100)]
  [int]$Repeat = 1,

  [string]$TemplatePath = ".\agent-task-template.single-tool.md",

  [string]$Model,

  [string]$OutputRoot,

  [ValidateRange(1, 1000)]
  [int]$MaxRuns = 10,

  [switch]$AllMatchingCases,

  [switch]$AllowLargeBatch,

  [switch]$SkipDependencyInstall,

  [switch]$DangerouslyBypassSandbox,

  [switch]$ContinueOnFailure,

  [switch]$PlanOnly,

  [switch]$ConfirmTokenSpend
)

$ErrorActionPreference = "Stop"

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

function Get-TokenStats {
  param([object[]]$Runs)

  if ($Runs.Count -eq 0) {
    return $null
  }

  $tokens = $Runs | Measure-Object -Property total_tokens -Minimum -Maximum -Average
  $average = [math]::Round($tokens.Average, 2)
  $range = [int64]($tokens.Maximum - $tokens.Minimum)

  return [pscustomobject]@{
    completed_runs = $Runs.Count
    min_total_tokens = [int64]$tokens.Minimum
    max_total_tokens = [int64]$tokens.Maximum
    range_total_tokens = $range
    range_total_tokens_pct_of_avg = if ($average -eq 0) { $null } else { [math]::Round(($range / $average) * 100, 4) }
    avg_total_tokens = $average
  }
}

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedCases = Resolve-Path -LiteralPath (Resolve-ProjectPath -Path $CasesPath -Root $root)
$resolvedTemplate = Resolve-Path -LiteralPath (Resolve-ProjectPath -Path $TemplatePath -Root $root)
$cases = @(Get-Content -Raw -LiteralPath $resolvedCases | ConvertFrom-Json)

$selectors = @(
  if ($RunId) { "RunId" }
  if (-not [string]::IsNullOrWhiteSpace($RepeatGroup)) { "RepeatGroup" }
  if ($AllMatchingCases) { "AllMatchingCases" }
)
if ($selectors.Count -ne 1) {
  throw "Specify exactly one selector: -RunId, -RepeatGroup, or -AllMatchingCases."
}

$selected = @(
  $cases | Where-Object {
    $scopeMatches = $Scope -eq "all" -or [string]$_.scope -eq $Scope
    $usablePath = -not [string]::IsNullOrWhiteSpace([string]$_.path) -and [string]$_.path -notlike "<*"
    $selectorMatches = if ($RunId) {
      [string]$_.id -in $RunId
    } elseif (-not [string]::IsNullOrWhiteSpace($RepeatGroup)) {
      [string]$_.repeat_group -eq $RepeatGroup
    } else {
      $true
    }
    $scopeMatches -and $usablePath -and $selectorMatches
  }
)

if ($RunId) {
  $foundIds = @($selected | ForEach-Object { [string]$_.id })
  $missingIds = @($RunId | Where-Object { [string]$_ -notin $foundIds })
  if ($missingIds.Count -gt 0) {
    throw "Selected case ids were not found in scope '$Scope': $($missingIds -join ', ')."
  }
}

if ($selected.Count -eq 0) {
  throw "No runnable cases matched the requested selection and scope '$Scope'."
}

$plannedRuns = $selected.Count * $Repeat
if ($plannedRuns -gt $MaxRuns -and -not $AllowLargeBatch) {
  throw "Planned run count $plannedRuns exceeds -MaxRuns $MaxRuns. Pass -AllowLargeBatch only after reviewing token spend."
}

$targetRoot = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  Join-Path $root ("live-runs\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
} else {
  Resolve-ProjectPath -Path $OutputRoot -Root $root
}

$selection = @(
  $selected | ForEach-Object {
    [pscustomobject]@{
      run_id = [string]$_.id
      repo = [string]$_.repo
      category = [string]$_.category
      repeat_group = if ($_.repeat_group) { [string]$_.repeat_group } else { $null }
    }
  }
)

$plan = [pscustomobject]@{
  status = "passed"
  mode = if ($PlanOnly) { "plan" } else { "live" }
  scope = $Scope
  repeat = $Repeat
  planned_runs = $plannedRuns
  output_root = $targetRoot
  template_path = $resolvedTemplate.Path
  token_spend_required = -not $PlanOnly
  selection = $selection
}

if ($PlanOnly) {
  $plan | ConvertTo-Json -Depth 8
  exit 0
}

if (-not $ConfirmTokenSpend) {
  throw "Live benchmark consumes token budget. Re-run with -ConfirmTokenSpend, or use -PlanOnly to preview the plan."
}

$resultsRoot = Join-Path $targetRoot "results"
$iterationsRoot = Join-Path $targetRoot "iterations"
New-Item -ItemType Directory -Path $resultsRoot -Force | Out-Null
New-Item -ItemType Directory -Path $iterationsRoot -Force | Out-Null

$runs = [System.Collections.Generic.List[object]]::new()
$hasFailure = $false

:iterationLoop for ($iteration = 1; $iteration -le $Repeat; $iteration++) {
  foreach ($case in $selected) {
    $caseId = [string]$case.id
    $iterationLabel = "repeat-{0:D3}" -f $iteration
    $caseOutputRoot = Join-Path $iterationsRoot (Join-Path $caseId $iterationLabel)

    try {
      $prepareParameters = @{
        CasesPath = $resolvedCases.Path
        Scope = $Scope
        RunId = @($caseId)
        Force = $true
      }
      if (-not $SkipDependencyInstall) {
        $prepareParameters.InstallDependencies = $true
      }

      $prepareResult = (& (Join-Path $PSScriptRoot "prepare-case-repos.ps1") @prepareParameters | Out-String).Trim() | ConvertFrom-Json
      if ([string]$prepareResult.status -ne "passed" -or [int]$prepareResult.prepared -ne 1) {
        throw "Fixture preparation failed or did not prepare exactly one case."
      }

      $runParameters = @{
        CasesPath = $resolvedCases.Path
        RunId = $caseId
        TemplatePath = $resolvedTemplate.Path
        OutputRoot = $caseOutputRoot
        Validate = $true
      }
      if ($Model) {
        $runParameters.Model = $Model
      }
      if ($DangerouslyBypassSandbox) {
        $runParameters.DangerouslyBypassSandbox = $true
      }

      Push-Location $root
      try {
        $runResult = (& (Join-Path $PSScriptRoot "run-codex-case.ps1") @runParameters | Out-String).Trim() | ConvertFrom-Json
      } finally {
        Pop-Location
      }

      if ($runResult.validation_passed -ne $true) {
        throw "Case validation did not pass after live run."
      }

      $resultPath = Join-Path $resultsRoot ("{0}--{1}.json" -f $caseId, $iterationLabel)
      Copy-Item -LiteralPath $runResult.result_path -Destination $resultPath -Force
      $runs.Add([pscustomobject]@{
        run_id = $caseId
        iteration = $iteration
        status = "passed"
        result_path = $resultPath
        event_path = [string]$runResult.event_path
        input_tokens = [int64]$runResult.input_tokens
        output_tokens = [int64]$runResult.output_tokens
        total_tokens = [int64]$runResult.total_tokens
        tool_calls = [int64]$runResult.tool_calls
        duration_seconds = [double]$runResult.duration_seconds
      }) | Out-Null
    } catch {
      $hasFailure = $true
      $runs.Add([pscustomobject]@{
        run_id = $caseId
        iteration = $iteration
        status = "failed"
        error = $_.Exception.Message
      }) | Out-Null
      if (-not $ContinueOnFailure) {
        break iterationLoop
      }
    }
  }
}

$passedRuns = @($runs | Where-Object { $_.status -eq "passed" })
$summaryPath = $null
if ($passedRuns.Count -gt 0) {
  $summaryPath = Join-Path $targetRoot "summary.json"
  $summaryJson = & (Join-Path $PSScriptRoot "summarize-token-results.ps1") -ResultsDir $resultsRoot -CasesPath $resolvedCases.Path
  Set-Content -LiteralPath $summaryPath -Value $summaryJson
}

$perCaseSummary = @(
  $passedRuns |
    Group-Object -Property run_id |
    Sort-Object -Property Name |
    ForEach-Object {
      $stats = Get-TokenStats -Runs @($_.Group)
      [pscustomobject]@{
        run_id = $_.Name
        completed_runs = $stats.completed_runs
        min_total_tokens = $stats.min_total_tokens
        max_total_tokens = $stats.max_total_tokens
        range_total_tokens = $stats.range_total_tokens
        range_total_tokens_pct_of_avg = $stats.range_total_tokens_pct_of_avg
        avg_total_tokens = $stats.avg_total_tokens
      }
    }
)

$manifest = [pscustomobject]@{
  status = if ($hasFailure) { "failed" } else { "passed" }
  mode = "live"
  scope = $Scope
  repeat = $Repeat
  planned_runs = $plannedRuns
  completed_runs = $runs.Count
  passed_runs = $passedRuns.Count
  output_root = $targetRoot
  summary_path = $summaryPath
  selection = $selection
  runs = $runs
  per_case_summary = $perCaseSummary
}

$manifestJson = $manifest | ConvertTo-Json -Depth 10
Set-Content -LiteralPath (Join-Path $targetRoot "manifest.json") -Value $manifestJson
$manifestJson

if ($hasFailure) {
  exit 1
}
