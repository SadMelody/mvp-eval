param(
  [Parameter(Mandatory = $true)]
  [string]$ResultsDir,

  [string]$CasesPath
)

$ErrorActionPreference = "Stop"

$resolvedResults = Resolve-Path -LiteralPath $ResultsDir
$resolvedCases = $null

if ($CasesPath) {
  $resolvedCases = Resolve-Path -LiteralPath $CasesPath
} else {
  $candidateCases = Join-Path -Path (Split-Path -Parent $resolvedResults) -ChildPath "cases.json"
  if (Test-Path -LiteralPath $candidateCases) {
    $resolvedCases = Resolve-Path -LiteralPath $candidateCases
  }
}

$casesById = @{}
if ($resolvedCases) {
  foreach ($case in (Get-Content -Raw -LiteralPath $resolvedCases | ConvertFrom-Json)) {
    $casesById[$case.id] = $case
  }
}

$files = Get-ChildItem -LiteralPath $resolvedResults -Filter *.json
$runs = @()

foreach ($file in $files) {
  $report = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
  $metrics = $report.runner_metrics
  $case = $casesById[$report.run_id]
  $budget = if ($case) { $case.token_budget } else { $null }
  $category = if ($case -and $case.category) { $case.category } else { "<unknown>" }
  $scope = if ($case -and $case.scope) { $case.scope } else { "<unknown>" }
  $repeatGroup = if ($case -and $case.repeat_group) { $case.repeat_group } else { $null }
  $expectedStatus = if ($case -and $case.expected -and $null -ne $case.expected.expected_status) { [string]$case.expected.expected_status } else { $null }

  $hasMetrics = (
    $null -ne $metrics.input_tokens -and
    $null -ne $metrics.output_tokens -and
    $null -ne $metrics.total_tokens -and
    $null -ne $metrics.tool_calls -and
    $null -ne $metrics.duration_seconds
  )

  $withinTokenBudget = if ($hasMetrics -and $budget -and $null -ne $budget.total_tokens) {
    [int64]$metrics.total_tokens -le [int64]$budget.total_tokens
  } else {
    $null
  }

  $withinToolBudget = if ($hasMetrics -and $budget -and $null -ne $budget.tool_calls) {
    [int64]$metrics.tool_calls -le [int64]$budget.tool_calls
  } else {
    $null
  }

  $withinDurationBudget = if ($hasMetrics -and $budget -and $null -ne $budget.duration_seconds) {
    [double]$metrics.duration_seconds -le [double]$budget.duration_seconds
  } else {
    $null
  }

  $budgetPassed = if ($hasMetrics -and $budget) {
    ($withinTokenBudget -ne $false) -and
    ($withinToolBudget -ne $false) -and
    ($withinDurationBudget -ne $false)
  } else {
    $false
  }

  $isExpectedNonPass = $expectedStatus -and $expectedStatus -ne "passed"
  $expectedStatusMatched = $expectedStatus -and $report.agent_report.status -eq $expectedStatus
  $expectedFailureValidated = $isExpectedNonPass -and $expectedStatusMatched -and $budgetPassed

  $failureReasons = @()
  if ($report.agent_report.status -ne "passed" -and $expectedFailureValidated) {
    $failureReasons += "expected_status_$($report.agent_report.status)"
  } elseif ($report.agent_report.status -ne "passed" -and $expectedStatus -and -not $expectedStatusMatched) {
    $failureReasons += "expected_status_mismatch"
  } elseif ($report.agent_report.status -ne "passed") {
    $failureReasons += "functional_status_$($report.agent_report.status)"
  }

  if (-not $hasMetrics) {
    $failureReasons += "missing_runner_metrics"
  }

  if ($null -eq $budget) {
    $failureReasons += "missing_case_budget"
  }

  if ($withinTokenBudget -eq $false) {
    $failureReasons += "total_token_budget_failed"
  }

  if ($withinToolBudget -eq $false) {
    $failureReasons += "tool_call_budget_failed"
  }

  if ($withinDurationBudget -eq $false) {
    $failureReasons += "duration_budget_failed"
  }

  $runs += [pscustomobject]@{
    run_id = $report.run_id
    repo = $report.repo
    category = $category
    scope = $scope
    repeat_group = $repeatGroup
    status = $report.agent_report.status
    expected_status = $expectedStatus
    expected_failure = $isExpectedNonPass
    expected_status_matched = $expectedStatusMatched
    expected_failure_validated = $expectedFailureValidated
    has_metrics = $hasMetrics
    has_case_budget = $null -ne $budget
    budget_passed = $budgetPassed
    mvp_passed = $report.agent_report.status -eq "passed" -and $budgetPassed
    failure_reasons = $failureReasons
    input_tokens = if ($hasMetrics) { [int64]$metrics.input_tokens } else { $null }
    output_tokens = if ($hasMetrics) { [int64]$metrics.output_tokens } else { $null }
    total_tokens = if ($hasMetrics) { [int64]$metrics.total_tokens } else { $null }
    tool_calls = if ($hasMetrics) { [int64]$metrics.tool_calls } else { $null }
    duration_seconds = if ($hasMetrics) { [double]$metrics.duration_seconds } else { $null }
    token_budget = if ($budget -and $null -ne $budget.total_tokens) { [int64]$budget.total_tokens } else { $null }
    tool_call_budget = if ($budget -and $null -ne $budget.tool_calls) { [int64]$budget.tool_calls } else { $null }
    duration_budget_seconds = if ($budget -and $null -ne $budget.duration_seconds) { [double]$budget.duration_seconds } else { $null }
    within_token_budget = $withinTokenBudget
    within_tool_call_budget = $withinToolBudget
    within_duration_budget = $withinDurationBudget
  }
}

$metricRuns = @($runs | Where-Object { $_.has_metrics })
$passedMetricRuns = @($metricRuns | Where-Object { $_.status -eq "passed" })
$budgetPassedMetricRuns = @($metricRuns | Where-Object { $_.budget_passed })
$mvpPassedRuns = @($metricRuns | Where-Object { $_.mvp_passed })
$expectedFailureValidatedRuns = @($metricRuns | Where-Object { $_.expected_failure_validated })

function Get-Average {
  param(
    [object[]]$Items,
    [string]$Property
  )

  if ($Items.Count -eq 0) {
    return $null
  }

  return [math]::Round((($Items | Measure-Object -Property $Property -Average).Average), 2)
}

function Get-Sum {
  param(
    [object[]]$Items,
    [string]$Property
  )

  if ($Items.Count -eq 0) {
    return 0
  }

  return [int64](($Items | Measure-Object -Property $Property -Sum).Sum)
}

function Get-Percentile {
  param(
    [object[]]$Items,
    [string]$Property,
    [double]$Percentile
  )

  $values = @(
    $Items |
      Where-Object { $null -ne $_.$Property } |
      ForEach-Object { [double]$_.$Property } |
      Sort-Object
  )

  if ($values.Count -eq 0) {
    return $null
  }

  if ($values.Count -eq 1) {
    return [math]::Round($values[0], 2)
  }

  $rank = ($Percentile / 100) * ($values.Count - 1)
  $lower = [math]::Floor($rank)
  $upper = [math]::Ceiling($rank)

  if ($lower -eq $upper) {
    return [math]::Round($values[$lower], 2)
  }

  $weight = $rank - $lower
  return [math]::Round(($values[$lower] * (1 - $weight)) + ($values[$upper] * $weight), 2)
}

function Get-RunStats {
  param([object[]]$Items)

  $metricItems = @($Items | Where-Object { $_.has_metrics })
  $passedItems = @($metricItems | Where-Object { $_.status -eq "passed" })
  $budgetPassedItems = @($metricItems | Where-Object { $_.budget_passed })
  $mvpPassedItems = @($metricItems | Where-Object { $_.mvp_passed })
  $expectedFailureValidatedItems = @($metricItems | Where-Object { $_.expected_failure_validated })

  return [pscustomobject]@{
    total_reports = $Items.Count
    reports_with_metrics = $metricItems.Count
    passed_reports_with_metrics = $passedItems.Count
    budget_passed_reports_with_metrics = $budgetPassedItems.Count
    mvp_passed_reports = $mvpPassedItems.Count
    expected_failure_validated_reports = $expectedFailureValidatedItems.Count
    functional_pass_rate = if ($metricItems.Count -eq 0) { 0 } else { [math]::Round($passedItems.Count / $metricItems.Count, 4) }
    mvp_pass_rate = if ($metricItems.Count -eq 0) { 0 } else { [math]::Round($mvpPassedItems.Count / $metricItems.Count, 4) }
    avg_total_tokens = Get-Average $metricItems "total_tokens"
    median_total_tokens = Get-Percentile $metricItems "total_tokens" 50
    p90_total_tokens = Get-Percentile $metricItems "total_tokens" 90
    avg_total_tokens_mvp_passed = Get-Average $mvpPassedItems "total_tokens"
    median_total_tokens_mvp_passed = Get-Percentile $mvpPassedItems "total_tokens" 50
    p90_total_tokens_mvp_passed = Get-Percentile $mvpPassedItems "total_tokens" 90
    avg_tool_calls = Get-Average $metricItems "tool_calls"
    avg_tool_calls_mvp_passed = Get-Average $mvpPassedItems "tool_calls"
    avg_duration_seconds = Get-Average $metricItems "duration_seconds"
    avg_duration_seconds_mvp_passed = Get-Average $mvpPassedItems "duration_seconds"
  }
}

$highestTokenRun = $null
if ($metricRuns.Count -gt 0) {
  $highestTokenRun = $metricRuns | Sort-Object -Property total_tokens -Descending | Select-Object -First 1
}

$category_summary = @(
  $runs |
    Group-Object -Property category |
    Sort-Object -Property Name |
    ForEach-Object {
      $stats = Get-RunStats @($_.Group)
      [pscustomobject]@{
        category = $_.Name
        total_reports = $stats.total_reports
        reports_with_metrics = $stats.reports_with_metrics
        passed_reports_with_metrics = $stats.passed_reports_with_metrics
        budget_passed_reports_with_metrics = $stats.budget_passed_reports_with_metrics
        mvp_passed_reports = $stats.mvp_passed_reports
        expected_failure_validated_reports = $stats.expected_failure_validated_reports
        functional_pass_rate = $stats.functional_pass_rate
        mvp_pass_rate = $stats.mvp_pass_rate
        avg_total_tokens = $stats.avg_total_tokens
        median_total_tokens = $stats.median_total_tokens
        p90_total_tokens = $stats.p90_total_tokens
        avg_total_tokens_mvp_passed = $stats.avg_total_tokens_mvp_passed
        median_total_tokens_mvp_passed = $stats.median_total_tokens_mvp_passed
        p90_total_tokens_mvp_passed = $stats.p90_total_tokens_mvp_passed
        avg_tool_calls = $stats.avg_tool_calls
        avg_tool_calls_mvp_passed = $stats.avg_tool_calls_mvp_passed
        avg_duration_seconds = $stats.avg_duration_seconds
        avg_duration_seconds_mvp_passed = $stats.avg_duration_seconds_mvp_passed
      }
    }
)

$scope_summary = @(
  $runs |
    Group-Object -Property scope |
    Sort-Object -Property Name |
    ForEach-Object {
      $stats = Get-RunStats @($_.Group)
      [pscustomobject]@{
        scope = $_.Name
        total_reports = $stats.total_reports
        reports_with_metrics = $stats.reports_with_metrics
        passed_reports_with_metrics = $stats.passed_reports_with_metrics
        budget_passed_reports_with_metrics = $stats.budget_passed_reports_with_metrics
        mvp_passed_reports = $stats.mvp_passed_reports
        expected_failure_validated_reports = $stats.expected_failure_validated_reports
        functional_pass_rate = $stats.functional_pass_rate
        mvp_pass_rate = $stats.mvp_pass_rate
        avg_total_tokens = $stats.avg_total_tokens
        median_total_tokens = $stats.median_total_tokens
        p90_total_tokens = $stats.p90_total_tokens
        avg_total_tokens_mvp_passed = $stats.avg_total_tokens_mvp_passed
        median_total_tokens_mvp_passed = $stats.median_total_tokens_mvp_passed
        p90_total_tokens_mvp_passed = $stats.p90_total_tokens_mvp_passed
        avg_tool_calls = $stats.avg_tool_calls
        avg_tool_calls_mvp_passed = $stats.avg_tool_calls_mvp_passed
        avg_duration_seconds = $stats.avg_duration_seconds
        avg_duration_seconds_mvp_passed = $stats.avg_duration_seconds_mvp_passed
      }
    }
)

$failure_reason_counts = @(
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

$repeat_summary = @(
  $runs |
    Where-Object { $_.repeat_group } |
    Group-Object -Property repeat_group |
    Sort-Object -Property Name |
    ForEach-Object {
      $stats = Get-RunStats @($_.Group)
      $metricGroup = @($_.Group | Where-Object { $_.has_metrics })
      $tokenStats = if ($metricGroup.Count -gt 0) { $metricGroup | Measure-Object -Property total_tokens -Minimum -Maximum -Average } else { $null }
      $tokenMin = if ($tokenStats) { [int64]$tokenStats.Minimum } else { $null }
      $tokenMax = if ($tokenStats) { [int64]$tokenStats.Maximum } else { $null }
      $tokenRange = if ($tokenStats) { [int64]($tokenStats.Maximum - $tokenStats.Minimum) } else { $null }
      $tokenAverage = if ($tokenStats) { [math]::Round($tokenStats.Average, 2) } else { $null }

      [pscustomobject]@{
        repeat_group = $_.Name
        total_reports = $stats.total_reports
        reports_with_metrics = $stats.reports_with_metrics
        mvp_passed_reports = $stats.mvp_passed_reports
        mvp_pass_rate = $stats.mvp_pass_rate
        min_total_tokens = $tokenMin
        max_total_tokens = $tokenMax
        range_total_tokens = $tokenRange
        range_total_tokens_pct_of_avg = if ($tokenAverage -and $tokenAverage -ne 0) { [math]::Round(($tokenRange / $tokenAverage) * 100, 4) } else { $null }
        avg_total_tokens = $tokenAverage
        median_total_tokens = $stats.median_total_tokens
        p90_total_tokens = $stats.p90_total_tokens
        avg_tool_calls = $stats.avg_tool_calls
        avg_duration_seconds = $stats.avg_duration_seconds
      }
    }
)

$summary = [pscustomobject]@{
  total_reports = $runs.Count
  reports_with_metrics = $metricRuns.Count
  metrics_capture_rate = if ($runs.Count -eq 0) { 0 } else { [math]::Round($metricRuns.Count / $runs.Count, 4) }
  passed_reports_with_metrics = $passedMetricRuns.Count
  budget_passed_reports_with_metrics = $budgetPassedMetricRuns.Count
  mvp_passed_reports = $mvpPassedRuns.Count
  expected_failure_validated_reports = $expectedFailureValidatedRuns.Count
  total_input_tokens = Get-Sum $metricRuns "input_tokens"
  total_output_tokens = Get-Sum $metricRuns "output_tokens"
  total_tokens = Get-Sum $metricRuns "total_tokens"
  avg_total_tokens_success = Get-Average $passedMetricRuns "total_tokens"
  avg_total_tokens_mvp_passed = Get-Average $mvpPassedRuns "total_tokens"
  median_total_tokens = Get-Percentile $metricRuns "total_tokens" 50
  p90_total_tokens = Get-Percentile $metricRuns "total_tokens" 90
  median_total_tokens_success = Get-Percentile $passedMetricRuns "total_tokens" 50
  p90_total_tokens_success = Get-Percentile $passedMetricRuns "total_tokens" 90
  median_total_tokens_mvp_passed = Get-Percentile $mvpPassedRuns "total_tokens" 50
  p90_total_tokens_mvp_passed = Get-Percentile $mvpPassedRuns "total_tokens" 90
  avg_tool_calls_success = Get-Average $passedMetricRuns "tool_calls"
  avg_tool_calls_mvp_passed = Get-Average $mvpPassedRuns "tool_calls"
  avg_duration_seconds_success = Get-Average $passedMetricRuns "duration_seconds"
  avg_duration_seconds_mvp_passed = Get-Average $mvpPassedRuns "duration_seconds"
  highest_token_run = $highestTokenRun
  failure_reason_counts = $failure_reason_counts
  category_summary = $category_summary
  scope_summary = $scope_summary
  repeat_summary = $repeat_summary
  runs = $runs
}

$summary | ConvertTo-Json -Depth 8
