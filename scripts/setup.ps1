param(
  [string]$Root = (Join-Path $PSScriptRoot "..")
)

$ErrorActionPreference = "Stop"

function Add-Check {
  param(
    [System.Collections.Generic.List[object]]$Checks,
    [string]$Name,
    [bool]$Required,
    [bool]$Passed,
    [string]$Summary
  )

  $Checks.Add([pscustomobject]@{
    name = $Name
    required = $Required
    passed = $Passed
    summary = $Summary
  }) | Out-Null
}

function Get-CommandSummary {
  param([string]$Name)

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    return $null
  }

  try {
    $version = & $Name --version 2>$null | Select-Object -First 1
    if ($version) {
      return [string]$version
    }
  } catch {
    return $command.Source
  }

  return $command.Source
}

$resolvedRoot = Resolve-Path -LiteralPath $Root
$checks = [System.Collections.Generic.List[object]]::new()

Add-Check -Checks $checks -Name "powershell" -Required $true -Passed ($PSVersionTable.PSVersion.Major -ge 5) -Summary "PowerShell $($PSVersionTable.PSVersion)"

foreach ($tool in @("git", "node", "npm")) {
  $summary = Get-CommandSummary -Name $tool
  Add-Check -Checks $checks -Name $tool -Required $true -Passed ($null -ne $summary) -Summary $(if ($summary) { $summary } else { "$tool was not found on PATH" })
}

$codexSummary = Get-CommandSummary -Name "codex"
Add-Check -Checks $checks -Name "codex_optional" -Required $false -Passed ($null -ne $codexSummary) -Summary $(if ($codexSummary) { $codexSummary } else { "optional; required only for live Agent smoke runs" })

foreach ($path in @(
  "cases.json",
  "evaluation.schema.json",
  "fixtures",
  "results",
  "scripts\verify-mvp-token-suite.ps1",
  ".github\workflows\mvp-token-suite.yml"
)) {
  $fullPath = Join-Path $resolvedRoot $path
  Add-Check -Checks $checks -Name "path:$path" -Required $true -Passed (Test-Path -LiteralPath $fullPath) -Summary $fullPath
}

$requiredFailures = @($checks | Where-Object { $_.required -and -not $_.passed })
$status = if ($requiredFailures.Count -eq 0) { "passed" } else { "failed" }

$report = [pscustomobject]@{
  status = $status
  root = $resolvedRoot.Path
  checks = $checks
  failed_checks = @($requiredFailures | Select-Object -ExpandProperty name)
}

$report | ConvertTo-Json -Depth 5

if ($requiredFailures.Count -gt 0) {
  exit 1
}
