param(
  [Parameter(Mandatory = $true)]
  [string]$SourceRepo,

  [Parameter(Mandatory = $true)]
  [string]$TargetRepo,

  [switch]$LinkNodeModules
)

$ErrorActionPreference = "Stop"

$resolvedSource = Resolve-Path -LiteralPath $SourceRepo
$target = $TargetRepo
if (-not [System.IO.Path]::IsPathRooted($target)) {
  $target = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $target))
}

if (Test-Path -LiteralPath $target) {
  throw "Target already exists: $target"
}

$targetParent = Split-Path -Parent $target
if (-not (Test-Path -LiteralPath $targetParent)) {
  New-Item -ItemType Directory -Path $targetParent | Out-Null
}

git clone $resolvedSource $target | Out-Host
if ($LASTEXITCODE -ne 0) {
  throw "git clone failed"
}

if ($LinkNodeModules) {
  $sourceNodeModules = Join-Path $resolvedSource "node_modules"
  $targetNodeModules = Join-Path $target "node_modules"

  if (-not (Test-Path -LiteralPath $sourceNodeModules)) {
    throw "Source node_modules not found: $sourceNodeModules"
  }

  New-Item -ItemType Junction -Path $targetNodeModules -Target $sourceNodeModules | Out-Null

  $excludePath = Join-Path $target ".git\info\exclude"
  Add-Content -LiteralPath $excludePath -Value "node_modules/"
}

Write-Output $target
