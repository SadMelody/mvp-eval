param(
  [Parameter(Mandatory = $true)]
  [string]$CasesPath,

  [Parameter(Mandatory = $true)]
  [string]$RunId,

  [string]$TemplatePath = ".\agent-task-template.md",

  [string]$Model,

  [string]$OutputRoot,

  [switch]$DangerouslyBypassSandbox,

  [switch]$Validate,

  [switch]$RefreshSummary
)

$ErrorActionPreference = "Stop"

$root = Get-Location
$outputRootPath = if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $root.Path
} elseif ([System.IO.Path]::IsPathRooted($OutputRoot)) {
  [System.IO.Path]::GetFullPath($OutputRoot)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $root $OutputRoot))
}
$resolvedCases = Resolve-Path -LiteralPath $CasesPath
$cases = Get-Content -Raw -LiteralPath $resolvedCases | ConvertFrom-Json
$case = @($cases | Where-Object { $_.id -eq $RunId }) | Select-Object -First 1

if ($null -eq $case) {
  throw "Case not found: $RunId"
}

$caseDir = Split-Path -Parent $resolvedCases
$repoPath = $case.path
if (-not [System.IO.Path]::IsPathRooted($repoPath)) {
  $repoPath = [System.IO.Path]::GetFullPath((Join-Path $caseDir $repoPath))
}

if (-not (Test-Path -LiteralPath $repoPath)) {
  throw "Repo path not found: $repoPath"
}

$promptPath = [System.IO.Path]::GetFullPath((Join-Path $outputRootPath "prompts\$RunId.md"))
$resultPath = [System.IO.Path]::GetFullPath((Join-Path $outputRootPath "results\$RunId.json"))
$eventPath = [System.IO.Path]::GetFullPath((Join-Path $outputRootPath "runs\$RunId\codex-events.jsonl"))
$lastMessagePath = [System.IO.Path]::GetFullPath((Join-Path $outputRootPath "runs\$RunId\last-message.json"))

foreach ($dir in @((Split-Path -Parent $promptPath), (Split-Path -Parent $resultPath), (Split-Path -Parent $eventPath))) {
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
  }
}

& (Join-Path $root "scripts\new-agent-prompt.ps1") -CasesPath $resolvedCases -RunId $RunId -TemplatePath $TemplatePath -OutputPath $promptPath | Out-Null

$arguments = @(
  "exec",
  "--json",
  "--ephemeral",
  "--ignore-user-config",
  "--ignore-rules",
  "--output-schema", (Join-Path $root "evaluation.schema.json"),
  "--output-last-message", $lastMessagePath,
  "--sandbox", "danger-full-access",
  "-C", $repoPath
)

if ($Model) {
  $arguments += @("--model", $Model)
}

if ($DangerouslyBypassSandbox) {
  $arguments += "--dangerously-bypass-approvals-and-sandbox"
}

$arguments += "-"

$start = Get-Date
$promptText = Get-Content -Raw -LiteralPath $promptPath
$output = $promptText | & codex @arguments 2>&1
$exitCode = $LASTEXITCODE
$duration = ((Get-Date) - $start).TotalSeconds
$output | Set-Content -LiteralPath $eventPath

if ($exitCode -ne 0) {
  throw "codex exec failed with exit code $exitCode. Events: $eventPath"
}

if (-not (Test-Path -LiteralPath $lastMessagePath)) {
  throw "Codex did not write last message: $lastMessagePath"
}

$lastMessage = Get-Content -Raw -LiteralPath $lastMessagePath
$jsonStart = $lastMessage.IndexOf("{")
$jsonEnd = $lastMessage.LastIndexOf("}")
if ($jsonStart -lt 0 -or $jsonEnd -lt $jsonStart) {
  throw "Last message did not contain JSON."
}

$reportJson = $lastMessage.Substring($jsonStart, $jsonEnd - $jsonStart + 1)
$reportJson | ConvertFrom-Json | Out-Null
$reportJson | Set-Content -LiteralPath $resultPath

$metricsJson = & (Join-Path $root "scripts\extract-runner-metrics.ps1") `
  -EventPath $eventPath `
  -DurationSeconds $duration `
  -Model $Model
$metrics = $metricsJson | ConvertFrom-Json

& (Join-Path $root "scripts\set-runner-metrics.ps1") `
  -ReportPath $resultPath `
  -Model $metrics.model `
  -InputTokens $metrics.input_tokens `
  -OutputTokens $metrics.output_tokens `
  -TotalTokens $metrics.total_tokens `
  -ToolCalls $metrics.tool_calls `
  -DurationSeconds $metrics.duration_seconds | Out-Null

$validation = $null
if ($Validate) {
  $validationJson = & (Join-Path $root "scripts\validate-run.ps1") `
    -RepoPath $repoPath `
    -ReportPath $resultPath `
    -RunId $RunId `
    -Repo $case.repo `
    -CasesPath $resolvedCases `
    -RequireRunnerMetrics

  $validation = $validationJson | ConvertFrom-Json
}

$summaryRefresh = $null
if ($RefreshSummary) {
  $summaryRefreshJson = & (Join-Path $root "scripts\refresh-token-summary.ps1") `
    -ReadmePath (Join-Path $root "README.md") `
    -ResultsDir (Join-Path $root "results") `
    -CasesPath $resolvedCases

  $summaryRefresh = $summaryRefreshJson | ConvertFrom-Json
}

[pscustomobject]@{
  run_id = $RunId
  repo_path = $repoPath
  result_path = $resultPath
  event_path = $eventPath
  input_tokens = $metrics.input_tokens
  output_tokens = $metrics.output_tokens
  total_tokens = $metrics.total_tokens
  cached_input_tokens = $metrics.cached_input_tokens
  reasoning_output_tokens = $metrics.reasoning_output_tokens
  tool_calls = $metrics.tool_calls
  duration_seconds = [math]::Round($duration, 2)
  validation_passed = if ($Validate) { [bool]$validation.passed } else { $null }
  summary_refresh_status = if ($RefreshSummary) { [string]$summaryRefresh.status } else { $null }
} | ConvertTo-Json -Depth 8
