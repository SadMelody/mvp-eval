param(
  [string]$ResultsDir = ".\results",

  [string]$CasesPath = ".\cases.json",

  [string]$Scope = "mvp",

  [int]$MinGroupSize = 2,

  [double]$MaxTokenRangePctOfAvg = 5.0,

  [string]$OutputPath = ".\token-stability.json",

  [string]$MarkdownPath = ".\TOKEN_STABILITY.md"
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

function Resolve-OutputPath {
  param(
    [string]$Root,
    [string]$Path
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function Add-Line {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Text = ""
  )

  $Lines.Add($Text) | Out-Null
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedResults = Resolve-Path -LiteralPath $ResultsDir
$resolvedCases = Resolve-Path -LiteralPath $CasesPath
$jsonTarget = Resolve-OutputPath -Root $root.Path -Path $OutputPath
$markdownTarget = Resolve-OutputPath -Root $root.Path -Path $MarkdownPath

$summaryJson = & (Join-Path $PSScriptRoot "summarize-token-results.ps1") -ResultsDir $resolvedResults -CasesPath $resolvedCases
$summary = $summaryJson | ConvertFrom-Json

$runs = @(
  $summary.runs |
    Where-Object {
      $_.repeat_group -and
      ($Scope -eq "all" -or [string]$_.scope -eq $Scope)
    }
)

$groups = @(
  $runs |
    Group-Object repeat_group |
    Sort-Object Name |
    Where-Object { $_.Count -ge $MinGroupSize } |
    ForEach-Object {
      $groupRuns = @($_.Group)
      $metricRuns = @($groupRuns | Where-Object { $_.has_metrics })
      $tokenValues = @($metricRuns | ForEach-Object { [double]$_.total_tokens })
      $toolValues = @($metricRuns | ForEach-Object { [double]$_.tool_calls })
      $durationValues = @($metricRuns | ForEach-Object { [double]$_.duration_seconds })
      $mvpPassed = @($groupRuns | Where-Object { $_.mvp_passed })

      $minTokens = if ($tokenValues.Count -gt 0) { [int64](($tokenValues | Measure-Object -Minimum).Minimum) } else { $null }
      $maxTokens = if ($tokenValues.Count -gt 0) { [int64](($tokenValues | Measure-Object -Maximum).Maximum) } else { $null }
      $avgTokens = if ($tokenValues.Count -gt 0) { [math]::Round((($tokenValues | Measure-Object -Average).Average), 2) } else { $null }
      $rangeTokens = if ($null -ne $minTokens -and $null -ne $maxTokens) { [int64]($maxTokens - $minTokens) } else { $null }
      $rangePct = if ($null -ne $avgTokens -and [double]$avgTokens -gt 0 -and $null -ne $rangeTokens) {
        [math]::Round(([double]$rangeTokens / [double]$avgTokens) * 100, 4)
      } else {
        $null
      }

      $metricsComplete = $metricRuns.Count -eq $groupRuns.Count
      $mvpClean = $mvpPassed.Count -eq $groupRuns.Count
      $stable = $null -ne $rangePct -and [double]$rangePct -le $MaxTokenRangePctOfAvg

      [pscustomobject]@{
        repeat_group = $_.Name
        status = if ($metricsComplete -and $mvpClean -and $stable) { "passed" } else { "failed" }
        total_reports = $groupRuns.Count
        reports_with_metrics = $metricRuns.Count
        mvp_passed_reports = $mvpPassed.Count
        mvp_pass_rate = if ($groupRuns.Count -eq 0) { 0 } else { [math]::Round($mvpPassed.Count / $groupRuns.Count, 4) }
        min_total_tokens = $minTokens
        max_total_tokens = $maxTokens
        avg_total_tokens = $avgTokens
        median_total_tokens = Get-Percentile $tokenValues 50
        p90_total_tokens = Get-Percentile $tokenValues 90
        range_total_tokens = $rangeTokens
        range_total_tokens_pct_of_avg = $rangePct
        max_allowed_range_pct_of_avg = $MaxTokenRangePctOfAvg
        avg_tool_calls = if ($toolValues.Count -gt 0) { [math]::Round((($toolValues | Measure-Object -Average).Average), 2) } else { $null }
        avg_duration_seconds = if ($durationValues.Count -gt 0) { [math]::Round((($durationValues | Measure-Object -Average).Average), 2) } else { $null }
        runs = @($groupRuns | Select-Object run_id, repo, category, status, mvp_passed, total_tokens, tool_calls, duration_seconds)
      }
    }
)

$failedGroups = @($groups | Where-Object { $_.status -ne "passed" })
$status = if ($groups.Count -gt 0 -and $failedGroups.Count -eq 0) { "passed" } else { "failed" }

$report = [pscustomobject]@{
  status = $status
  scope = $Scope
  results_dir = $resolvedResults.Path
  cases = $resolvedCases.Path
  min_group_size = $MinGroupSize
  max_token_range_pct_of_avg = $MaxTokenRangePctOfAvg
  totals = [pscustomobject]@{
    repeat_groups = $groups.Count
    failed_repeat_groups = $failedGroups.Count
    repeat_runs = $runs.Count
  }
  repeat_groups = $groups
  failed_groups = @($failedGroups | Select-Object repeat_group, range_total_tokens_pct_of_avg, max_allowed_range_pct_of_avg, reports_with_metrics, total_reports, mvp_passed_reports)
}

$jsonDir = Split-Path -Parent $jsonTarget
if (-not (Test-Path -LiteralPath $jsonDir)) {
  New-Item -ItemType Directory -Path $jsonDir | Out-Null
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonTarget

$lines = [System.Collections.Generic.List[string]]::new()
Add-Line $lines "# Token Stability Report"
Add-Line $lines
Add-Line $lines "- Status: **$status**"
Add-Line $lines "- Scope: $Scope"
Add-Line $lines "- Repeat groups: $($groups.Count)"
Add-Line $lines "- Failed repeat groups: $($failedGroups.Count)"
Add-Line $lines "- Max allowed token range pct of average: $MaxTokenRangePctOfAvg"
Add-Line $lines
Add-Line $lines "| Repeat group | Runs | MVP passed | Min tokens | Max tokens | Range | Range pct of avg | Status |"
Add-Line $lines "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |"
foreach ($group in $groups) {
  Add-Line $lines "| $($group.repeat_group) | $($group.total_reports) | $($group.mvp_passed_reports) | $($group.min_total_tokens) | $($group.max_total_tokens) | $($group.range_total_tokens) | $($group.range_total_tokens_pct_of_avg) | $($group.status) |"
}

$markdownDir = Split-Path -Parent $markdownTarget
if (-not (Test-Path -LiteralPath $markdownDir)) {
  New-Item -ItemType Directory -Path $markdownDir | Out-Null
}
Set-Content -LiteralPath $markdownTarget -Value ($lines -join [Environment]::NewLine)

$report | ConvertTo-Json -Depth 10

if ($status -ne "passed") {
  exit 1
}
