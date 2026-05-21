param(
  [string]$ResultsDir = ".\results",
  [string]$CasesPath = ".\cases.json",
  [string]$Scope = "mvp",
  [int]$Top = 10,
  [double]$TokenBudgetRatioWarn = 0.85,
  [double]$ToolCallBudgetRatioWarn = 0.85,
  [double]$DurationBudgetRatioWarn = 0.85,
  [double]$TokenP90MultiplierWarn = 1.25
)

$ErrorActionPreference = "Stop"

function Test-ScopeMatch {
  param([object]$Run)

  if ($Scope -eq "all") {
    return $true
  }

  return [string]$Run.scope -eq $Scope
}

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

function Get-Ratio {
  param(
    [object]$Value,
    [object]$Budget
  )

  if ($null -eq $Value -or $null -eq $Budget -or [double]$Budget -le 0) {
    return $null
  }

  return [math]::Round(([double]$Value / [double]$Budget), 4)
}

function Select-RunFields {
  param([object]$Run)

  [pscustomobject]@{
    run_id = $Run.run_id
    repo = $Run.repo
    category = $Run.category
    scope = $Run.scope
    status = $Run.status
    mvp_passed = $Run.mvp_passed
    expected_failure_validated = $Run.expected_failure_validated
    total_tokens = $Run.total_tokens
    token_budget = $Run.token_budget
    token_budget_ratio = Get-Ratio $Run.total_tokens $Run.token_budget
    tool_calls = $Run.tool_calls
    tool_call_budget = $Run.tool_call_budget
    tool_call_budget_ratio = Get-Ratio $Run.tool_calls $Run.tool_call_budget
    duration_seconds = $Run.duration_seconds
    duration_budget_seconds = $Run.duration_budget_seconds
    duration_budget_ratio = Get-Ratio $Run.duration_seconds $Run.duration_budget_seconds
    failure_reasons = @($Run.failure_reasons)
  }
}

function Get-CategoryAnalysis {
  param([object[]]$Runs)

  @(
    $Runs |
      Group-Object category |
      Sort-Object -Property Name |
      ForEach-Object {
        $group = @($_.Group | Where-Object { $_.has_metrics })
        $tokenValues = @($group | Where-Object { $null -ne $_.total_tokens } | ForEach-Object { [double]$_.total_tokens })
        $ratios = @($group | ForEach-Object { Get-Ratio $_.total_tokens $_.token_budget } | Where-Object { $null -ne $_ })
        $passed = @($group | Where-Object { $_.mvp_passed })
        $nonMvp = @($group | Where-Object { -not $_.mvp_passed -and -not $_.expected_failure_validated })

        [pscustomobject]@{
          category = $_.Name
          reports_with_metrics = $group.Count
          mvp_passed_reports = $passed.Count
          non_mvp_reports = $nonMvp.Count
          mvp_pass_rate = if ($group.Count -eq 0) { 0 } else { [math]::Round($passed.Count / $group.Count, 4) }
          median_total_tokens = Get-Percentile $tokenValues 50
          p90_total_tokens = Get-Percentile $tokenValues 90
          max_total_tokens = if ($tokenValues.Count -eq 0) { $null } else { [int64]($tokenValues | Measure-Object -Maximum).Maximum }
          median_token_budget_ratio = Get-Percentile $ratios 50
          p90_token_budget_ratio = Get-Percentile $ratios 90
        }
      }
  )
}

$summaryJson = & (Join-Path $PSScriptRoot "summarize-token-results.ps1") -ResultsDir $ResultsDir -CasesPath $CasesPath
$summary = $summaryJson | ConvertFrom-Json
$runs = @($summary.runs | Where-Object { Test-ScopeMatch $_ })
$metricRuns = @($runs | Where-Object { $_.has_metrics })
$tokenValues = @($metricRuns | Where-Object { $null -ne $_.total_tokens } | ForEach-Object { [double]$_.total_tokens })
$tokenP90 = Get-Percentile $tokenValues 90
$tokenOutlierThreshold = if ($null -eq $tokenP90) { $null } else { [math]::Round($tokenP90 * $TokenP90MultiplierWarn, 4) }

$enrichedRuns = @(
  $metricRuns |
    ForEach-Object {
      $selected = Select-RunFields $_
      Add-Member -InputObject $selected -NotePropertyName "token_p90_outlier" -NotePropertyValue ($null -ne $tokenOutlierThreshold -and $null -ne $_.total_tokens -and [double]$_.total_tokens -gt $tokenOutlierThreshold)
      Add-Member -InputObject $selected -NotePropertyName "near_token_budget" -NotePropertyValue ($null -ne $selected.token_budget_ratio -and [double]$selected.token_budget_ratio -ge $TokenBudgetRatioWarn)
      Add-Member -InputObject $selected -NotePropertyName "near_tool_call_budget" -NotePropertyValue ($null -ne $selected.tool_call_budget_ratio -and [double]$selected.tool_call_budget_ratio -ge $ToolCallBudgetRatioWarn)
      Add-Member -InputObject $selected -NotePropertyName "near_duration_budget" -NotePropertyValue ($null -ne $selected.duration_budget_ratio -and [double]$selected.duration_budget_ratio -ge $DurationBudgetRatioWarn)
      $selected
    }
)

$missingMetrics = @($runs | Where-Object { -not $_.has_metrics } | ForEach-Object {
  [pscustomobject]@{
    run_id = $_.run_id
    repo = $_.repo
    category = $_.category
    scope = $_.scope
    status = $_.status
    failure_reasons = @($_.failure_reasons)
  }
})

$nonMvpRuns = @(
  $enrichedRuns |
    Where-Object { -not $_.mvp_passed -and -not $_.expected_failure_validated } |
    Sort-Object -Property total_tokens -Descending
)

$warningRuns = @(
  $enrichedRuns |
    Where-Object { $_.token_p90_outlier -or $_.near_token_budget -or $_.near_tool_call_budget -or $_.near_duration_budget } |
    Sort-Object -Property token_budget_ratio, total_tokens -Descending
)

$failureReasons = @(
  $runs |
    ForEach-Object { $_.failure_reasons } |
    Where-Object { $_ } |
    Group-Object |
    Sort-Object -Property @{Expression = "Count"; Descending = $true}, Name |
    ForEach-Object {
      [pscustomobject]@{
        reason = $_.Name
        count = $_.Count
      }
    }
)

$topTotalTokens = @($enrichedRuns | Sort-Object -Property total_tokens -Descending | Select-Object -First $Top)
$topBudgetRatios = @($enrichedRuns | Where-Object { $null -ne $_.token_budget_ratio } | Sort-Object -Property token_budget_ratio -Descending | Select-Object -First $Top)
$topToolCalls = @($enrichedRuns | Sort-Object -Property tool_calls -Descending | Select-Object -First $Top)
$topDurations = @($enrichedRuns | Sort-Object -Property duration_seconds -Descending | Select-Object -First $Top)

$categoryAnalysis = Get-CategoryAnalysis $runs
$categoryHotspots = @(
  $categoryAnalysis |
    Where-Object { $_.reports_with_metrics -gt 0 } |
    Sort-Object -Property p90_token_budget_ratio, p90_total_tokens -Descending |
    Select-Object -First $Top
)

$status = if ($metricRuns.Count -eq 0) {
  "failed"
} elseif ($missingMetrics.Count -gt 0 -or $nonMvpRuns.Count -gt 0 -or $warningRuns.Count -gt 0) {
  "warning"
} else {
  "passed"
}

[pscustomobject]@{
  status = $status
  scope = $Scope
  thresholds = [pscustomobject]@{
    token_budget_ratio_warn = $TokenBudgetRatioWarn
    tool_call_budget_ratio_warn = $ToolCallBudgetRatioWarn
    duration_budget_ratio_warn = $DurationBudgetRatioWarn
    token_p90_multiplier_warn = $TokenP90MultiplierWarn
    token_p90 = $tokenP90
    token_p90_outlier_threshold = $tokenOutlierThreshold
  }
  totals = [pscustomobject]@{
    reports = $runs.Count
    reports_with_metrics = $metricRuns.Count
    missing_metrics = $missingMetrics.Count
    non_mvp_reports = $nonMvpRuns.Count
    warning_reports = $warningRuns.Count
  }
  failure_reason_counts = $failureReasons
  top_total_tokens = $topTotalTokens
  top_token_budget_ratios = $topBudgetRatios
  top_tool_calls = $topToolCalls
  top_durations = $topDurations
  warning_runs = $warningRuns
  non_mvp_runs = $nonMvpRuns
  missing_metric_runs = $missingMetrics
  category_hotspots = $categoryHotspots
  category_analysis = $categoryAnalysis
} | ConvertTo-Json -Depth 8
