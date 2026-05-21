param(
  [Parameter(Mandatory = $true)]
  [string]$CasesPath,

  [Parameter(Mandatory = $true)]
  [string]$RunId,

  [string]$TemplatePath = ".\agent-task-template.md",

  [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$resolvedCases = Resolve-Path -LiteralPath $CasesPath
$resolvedTemplate = Resolve-Path -LiteralPath $TemplatePath
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

$prompt = Get-Content -Raw -LiteralPath $resolvedTemplate
$prompt = $prompt.Replace("{{REPO_PATH}}", $repoPath)
$prompt = $prompt.Replace("{{RUN_ID}}", $case.id)
$prompt = $prompt.Replace("{{REPO}}", $case.repo)
$prompt = $prompt.Replace("{{TASK}}", $case.task)

if ($OutputPath) {
  $target = $OutputPath
  if (-not [System.IO.Path]::IsPathRooted($target)) {
    $target = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $target))
  }

  $targetDir = Split-Path -Parent $target
  if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
  }

  Set-Content -LiteralPath $target -Value $prompt -NoNewline
  Write-Output $target
} else {
  Write-Output $prompt
}
