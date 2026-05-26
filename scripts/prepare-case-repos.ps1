param(
  [string]$CasesPath = ".\cases.json",
  [string]$Scope = "mvp",
  [string[]]$RunId,
  [switch]$Force,
  [switch]$InstallDependencies
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

function Copy-DirectoryWithoutGitState {
  param(
    [string]$Source,
    [string]$Destination
  )

  New-Item -ItemType Directory -Path $Destination -Force | Out-Null

  $sourceRoot = (Resolve-Path -LiteralPath $Source).Path
  foreach ($item in Get-ChildItem -LiteralPath $sourceRoot -Force -Recurse) {
    $relative = [System.IO.Path]::GetRelativePath($sourceRoot, $item.FullName)
    $parts = $relative -split '[\\/]'
    if ($parts -contains ".git" -or $parts -contains "node_modules") {
      continue
    }

    $target = Join-Path $Destination $relative
    if ($item.PSIsContainer) {
      New-Item -ItemType Directory -Path $target -Force | Out-Null
    } else {
      $targetDir = Split-Path -Parent $target
      if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
      }
      Copy-Item -LiteralPath $item.FullName -Destination $target -Force
    }
  }
}

function Invoke-Git {
  param(
    [string]$RepoPath,
    [string[]]$Arguments
  )

  $output = & git -C $RepoPath @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "git -C $RepoPath $($Arguments -join ' ') failed: $($output | Out-String)"
  }
}

function Install-NpmDependencies {
  param([string]$RepoPath)

  $packagePath = Join-Path $RepoPath "package.json"
  if (-not (Test-Path -LiteralPath $packagePath)) {
    return "no_package"
  }

  $package = Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json
  $dependencyGroups = @($package.dependencies, $package.devDependencies, $package.optionalDependencies, $package.peerDependencies)
  $hasDependencies = $false
  foreach ($group in $dependencyGroups) {
    if ($null -ne $group -and $group.PSObject.Properties.Count -gt 0) {
      $hasDependencies = $true
      break
    }
  }

  if (-not $hasDependencies) {
    return "no_dependencies"
  }

  if (Test-Path -LiteralPath (Join-Path $RepoPath "node_modules")) {
    return "node_modules_present"
  }

  Push-Location $RepoPath
  try {
    $output = & npm install --ignore-scripts --no-audit --fund=false --loglevel=error 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "npm install failed in $RepoPath`: $($output | Out-String)"
    }
  } finally {
    Pop-Location
  }

  return "installed"
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedCases = Resolve-Path -LiteralPath $CasesPath
$cases = @(Get-Content -Raw -LiteralPath $resolvedCases | ConvertFrom-Json)
$prepared = [System.Collections.Generic.List[object]]::new()

foreach ($case in $cases) {
  if ($Scope -ne "all" -and [string]$case.scope -ne $Scope) {
    continue
  }

  if ($RunId -and [string]$case.id -notin $RunId) {
    continue
  }

  if ([string]::IsNullOrWhiteSpace([string]$case.path) -or [string]$case.path -like "<*") {
    continue
  }

  $targetRepo = Resolve-ProjectPath -Path ([string]$case.path) -Root $root.Path
  $caseBase = Join-Path $root.Path "fixtures\case-bases\$($case.id)"
  $repoBase = Join-Path $root.Path "fixtures\$($case.repo)"
  $patchPath = Join-Path $root.Path "fixtures\patches\$($case.id).patch"
  $overlayPath = Join-Path $root.Path "fixtures\final-overlays\$($case.id)"
  $basePath = if (Test-Path -LiteralPath $caseBase) { $caseBase } elseif (Test-Path -LiteralPath $repoBase) { $repoBase } else { $null }

  if ($null -eq $basePath) {
    $prepared.Add([pscustomobject]@{
      run_id = [string]$case.id
      status = "skipped"
      reason = "base_fixture_not_found"
      path = $targetRepo
    }) | Out-Null
    continue
  }

  $targetGit = Join-Path $targetRepo ".git"
  if ((Test-Path -LiteralPath $targetGit) -and -not $Force) {
    $dependencyStatus = if ($InstallDependencies) { Install-NpmDependencies -RepoPath $targetRepo } else { "not_requested" }
    $prepared.Add([pscustomobject]@{
      run_id = [string]$case.id
      status = "skipped"
      reason = "repo_already_prepared"
      path = $targetRepo
      dependency_status = $dependencyStatus
    }) | Out-Null
    continue
  }

  if (Test-Path -LiteralPath $targetRepo) {
    $resolvedTarget = [System.IO.Path]::GetFullPath($targetRepo)
    $runsRoot = [System.IO.Path]::GetFullPath((Join-Path $root.Path "runs"))
    if (-not $resolvedTarget.StartsWith($runsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Refusing to remove repo outside runs directory: $resolvedTarget"
    }
    Remove-Item -LiteralPath $targetRepo -Recurse -Force
  }

  Copy-DirectoryWithoutGitState -Source $basePath -Destination $targetRepo
  Invoke-Git -RepoPath $targetRepo -Arguments @("init", "-q")
  Invoke-Git -RepoPath $targetRepo -Arguments @("config", "core.autocrlf", "false")
  Invoke-Git -RepoPath $targetRepo -Arguments @("add", "-A")
  Invoke-Git -RepoPath $targetRepo -Arguments @("-c", "user.name=MVP Eval", "-c", "user.email=mvp-eval@example.invalid", "commit", "-m", "Fixture baseline", "-q")

  $patchApplied = $false
  if (Test-Path -LiteralPath $patchPath) {
    $patch = Get-Item -LiteralPath $patchPath
    if ($patch.Length -gt 0) {
      Invoke-Git -RepoPath $targetRepo -Arguments @("apply", "--binary", "--ignore-whitespace", $patchPath)
      $untracked = @(& git -C $targetRepo ls-files --others --exclude-standard)
      if ($untracked.Count -gt 0) {
        $intentToAddArguments = @("add", "-N", "--") + $untracked
        Invoke-Git -RepoPath $targetRepo -Arguments $intentToAddArguments
      }
      $patchApplied = $true
    }
  }

  if (Test-Path -LiteralPath $overlayPath) {
    Copy-DirectoryWithoutGitState -Source $overlayPath -Destination $targetRepo
  }

  $prepared.Add([pscustomobject]@{
    run_id = [string]$case.id
    status = "prepared"
    reason = if ($patchApplied) { "base_plus_patch" } else { "base_only" }
    path = $targetRepo
    dependency_status = if ($InstallDependencies) { Install-NpmDependencies -RepoPath $targetRepo } else { "not_requested" }
  }) | Out-Null
}

$failed = @($prepared | Where-Object { $_.status -eq "skipped" -and $_.reason -eq "base_fixture_not_found" })
$status = if ($failed.Count -eq 0) { "passed" } else { "failed" }

[pscustomobject]@{
  status = $status
  scope = $Scope
  run_ids = @($RunId)
  prepared = @($prepared | Where-Object { $_.status -eq "prepared" }).Count
  skipped = @($prepared | Where-Object { $_.status -eq "skipped" }).Count
  failed = $failed
  results = $prepared
} | ConvertTo-Json -Depth 8

if ($failed.Count -gt 0) {
  exit 1
}
