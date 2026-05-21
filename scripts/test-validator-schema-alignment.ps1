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

function Copy-JsonObject {
  param([object]$Value)
  return ($Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function Get-SchemaObjectSpecs {
  param([object]$Schema)

  $agentSchema = $Schema.properties.agent_report
  $commandSchema = $agentSchema.properties.commands_run.items
  $verificationSchema = $agentSchema.properties.verification
  $riskSchema = $agentSchema.properties.risk
  $metricsSchema = $Schema.properties.runner_metrics

  return @(
    [pscustomobject]@{
      name = "top_level"
      required = @($Schema.required | ForEach-Object { [string]$_ })
      exact_check = "schema.top_level.exact"
    }
    [pscustomobject]@{
      name = "agent_report"
      required = @($agentSchema.required | ForEach-Object { [string]$_ })
      exact_check = "schema.agent_report.exact"
    }
    [pscustomobject]@{
      name = "runner_metrics"
      required = @($metricsSchema.required | ForEach-Object { [string]$_ })
      exact_check = "schema.runner_metrics.exact"
    }
    [pscustomobject]@{
      name = "command"
      required = @($commandSchema.required | ForEach-Object { [string]$_ })
      exact_check = "schema.commands_run.items"
    }
    [pscustomobject]@{
      name = "verification"
      required = @($verificationSchema.required | ForEach-Object { [string]$_ })
      exact_check = "schema.verification.exact"
    }
    [pscustomobject]@{
      name = "risk"
      required = @($riskSchema.required | ForEach-Object { [string]$_ })
      exact_check = "schema.risk.exact"
    }
  )
}

function Get-TargetObject {
  param(
    [object]$Report,
    [string]$Name
  )

  switch ($Name) {
    "top_level" { return $Report }
    "agent_report" { return $Report.agent_report }
    "runner_metrics" { return $Report.runner_metrics }
    "command" { return @($Report.agent_report.commands_run)[0] }
    "verification" { return $Report.agent_report.verification }
    "risk" { return $Report.agent_report.risk }
    default { throw "Unknown schema object spec: $Name" }
  }
}

function Invoke-Validator {
  param(
    [string]$RepoPath,
    [string]$ReportPath,
    [string]$RunId,
    [string]$Repo,
    [string]$CasesPath
  )

  $output = & (Join-Path $PSScriptRoot "validate-run.ps1") `
    -RepoPath $RepoPath `
    -ReportPath $ReportPath `
    -RunId $RunId `
    -Repo $Repo `
    -CasesPath $CasesPath `
    -RequireRunnerMetrics 2>&1

  $exitCode = $LASTEXITCODE
  $jsonText = ($output | Out-String).Trim()
  $validation = $jsonText | ConvertFrom-Json
  $failedNames = @($validation.results | Where-Object { -not $_.passed } | ForEach-Object { [string]$_.name })

  return [pscustomobject]@{
    passed = ($exitCode -eq 0 -and [bool]$validation.passed)
    exit_code = $exitCode
    failed_checks = $failedNames
  }
}

function Invoke-ValidatorExpectFailure {
  param(
    [string]$Name,
    [string]$RepoPath,
    [string]$ReportPath,
    [string]$RunId,
    [string]$Repo,
    [string]$CasesPath,
    [string[]]$ExpectedFailedChecks
  )

  $validation = Invoke-Validator `
    -RepoPath $RepoPath `
    -ReportPath $ReportPath `
    -RunId $RunId `
    -Repo $Repo `
    -CasesPath $CasesPath

  $missingExpected = @($ExpectedFailedChecks | Where-Object { $validation.failed_checks -notcontains $_ })

  return [pscustomobject]@{
    name = $Name
    passed = ($validation.exit_code -ne 0 -and -not $validation.passed -and $missingExpected.Count -eq 0)
    failed_checks = $validation.failed_checks
    missing_expected_checks = $missingExpected
  }
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$schemaPath = Join-Path $root "evaluation.schema.json"
$casesPath = Join-Path $root "cases.json"
$sourceReportPath = Join-Path $root "results\unit-string-trim-basic-token-single-001.json"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("mvp-schema-alignment-" + [System.Guid]::NewGuid().ToString("N"))
$results = [System.Collections.Generic.List[object]]::new()

try {
  New-Item -ItemType Directory -Path $tempRoot | Out-Null

  $schema = Get-Content -Raw -LiteralPath $schemaPath | ConvertFrom-Json
  $sourceReport = Get-Content -Raw -LiteralPath $sourceReportPath | ConvertFrom-Json
  $sourceCase = Get-Content -Raw -LiteralPath $casesPath |
    ConvertFrom-Json |
    Where-Object { $_.id -eq "unit-string-trim-basic-token-single-001" } |
    Select-Object -First 1
  $sourceRepo = [string]$sourceCase.path

  $goodValidation = Invoke-Validator `
    -RepoPath $sourceRepo `
    -ReportPath $sourceReportPath `
    -RunId "unit-string-trim-basic-token-single-001" `
    -Repo "unit-string-trim-basic" `
    -CasesPath $casesPath
  Add-Result $results "schema_alignment.good_report" $goodValidation.passed "source report must pass validator before mutation tests."

  $checks = [System.Collections.Generic.List[object]]::new()
  foreach ($spec in Get-SchemaObjectSpecs $schema) {
    $extraReport = Copy-JsonObject $sourceReport
    $extraTarget = Get-TargetObject -Report $extraReport -Name $spec.name
    Add-Member -InputObject $extraTarget -NotePropertyName "schema_alignment_extra" -NotePropertyValue $true
    $extraPath = Join-Path $tempRoot "$($spec.name)-extra.json"
    $extraReport | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $extraPath
    $checks.Add((Invoke-ValidatorExpectFailure `
      -Name "schema_alignment.extra.$($spec.name)" `
      -RepoPath $sourceRepo `
      -ReportPath $extraPath `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @($spec.exact_check))) | Out-Null

    foreach ($field in $spec.required) {
      $missingReport = Copy-JsonObject $sourceReport
      $missingTarget = Get-TargetObject -Report $missingReport -Name $spec.name
      $missingTarget.PSObject.Properties.Remove($field)
      $missingPath = Join-Path $tempRoot "$($spec.name)-missing-$field.json"
      $missingReport | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $missingPath
      $checks.Add((Invoke-ValidatorExpectFailure `
        -Name "schema_alignment.required.$($spec.name).$field" `
        -RepoPath $sourceRepo `
        -ReportPath $missingPath `
        -RunId "unit-string-trim-basic-token-single-001" `
        -Repo "unit-string-trim-basic" `
        -CasesPath $casesPath `
        -ExpectedFailedChecks @($spec.exact_check))) | Out-Null
    }
  }

  $enumTests = @(
    [pscustomobject]@{
      name = "agent_status"
      expected_check = "schema.status"
      mutate = {
        param([object]$Report)
        $Report.agent_report.status = "schema-alignment-invalid"
      }
    }
    [pscustomobject]@{
      name = "command_status"
      expected_check = "schema.commands_run.items"
      mutate = {
        param([object]$Report)
        @($Report.agent_report.commands_run)[0].status = "schema-alignment-invalid"
      }
    }
    [pscustomobject]@{
      name = "risk_level"
      expected_check = "schema.risk.level"
      mutate = {
        param([object]$Report)
        $Report.agent_report.risk.level = "schema-alignment-invalid"
      }
    }
  )

  foreach ($enumTest in $enumTests) {
    $enumReport = Copy-JsonObject $sourceReport
    & $enumTest.mutate $enumReport
    $enumPath = Join-Path $tempRoot "$($enumTest.name)-enum.json"
    $enumReport | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $enumPath
    $checks.Add((Invoke-ValidatorExpectFailure `
      -Name "schema_alignment.enum.$($enumTest.name)" `
      -RepoPath $sourceRepo `
      -ReportPath $enumPath `
      -RunId "unit-string-trim-basic-token-single-001" `
      -Repo "unit-string-trim-basic" `
      -CasesPath $casesPath `
      -ExpectedFailedChecks @($enumTest.expected_check))) | Out-Null
  }

  foreach ($check in $checks) {
    Add-Result $results $check.name $check.passed ("failed_checks=[$($check.failed_checks -join ', ')]; missing_expected=[$($check.missing_expected_checks -join ', ')]")
  }

  $failed = @($results | Where-Object { -not $_.passed })
  $status = if ($failed.Count -eq 0) { "passed" } else { "failed" }

  [pscustomobject]@{
    status = $status
    temp_root = $tempRoot
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
