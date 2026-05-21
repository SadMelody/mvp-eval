param(
  [string]$CasesPath = ".\cases.json",

  [string]$Scope = "mvp",

  [int]$MinCasesPerCategory = 3,

  [int]$MinRepeatGroups = 2,

  [int]$MinRepeatGroupSize = 3,

  [int]$MinRealRepoCases = 3,

  [string]$OutputPath = ".\coverage-gaps.json",

  [string]$MarkdownPath = ".\COVERAGE_GAPS.md"
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

function Add-Line {
  param(
    [System.Collections.Generic.List[string]]$Lines,
    [string]$Text = ""
  )

  $Lines.Add($Text) | Out-Null
}

function Get-RepeatGroup {
  param([object]$Case)

  if ($Case.PSObject.Properties.Name -contains "repeat_group" -and -not [string]::IsNullOrWhiteSpace([string]$Case.repeat_group)) {
    return [string]$Case.repeat_group
  }

  return $null
}

function Test-RealRepoCase {
  param([object]$Case)

  return ([string]$Case.category -like "*real-repo*") -or ([string]$Case.scenario -like "real-package*")
}

$root = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedCases = Resolve-Path -LiteralPath (Resolve-ProjectPath -Path $CasesPath -Root $root.Path)
$target = Resolve-ProjectPath -Path $OutputPath -Root $root.Path
$markdownTarget = Resolve-ProjectPath -Path $MarkdownPath -Root $root.Path

$cases = @(Get-Content -Raw -LiteralPath $resolvedCases.Path | ConvertFrom-Json)
$scopedCases = @($cases | Where-Object { $Scope -eq "all" -or [string]$_.scope -eq $Scope })

$categoryCoverage = @(
  $scopedCases |
    Group-Object -Property category |
    Sort-Object -Property Name |
    ForEach-Object {
      $groupCases = @($_.Group)
      $repeatGroups = @(
        $groupCases |
          ForEach-Object { Get-RepeatGroup -Case $_ } |
          Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
          Select-Object -Unique
      )
      $realRepoCases = @($groupCases | Where-Object { Test-RealRepoCase -Case $_ })

      [pscustomobject]@{
        category = [string]$_.Name
        total_cases = $groupCases.Count
        real_repo_cases = $realRepoCases.Count
        repeat_group_cases = @($groupCases | Where-Object { -not [string]::IsNullOrWhiteSpace((Get-RepeatGroup -Case $_)) }).Count
        repeat_groups = $repeatGroups.Count
        below_min_cases = $groupCases.Count -lt $MinCasesPerCategory
      }
    }
)

$repeatGroupCoverage = @(
  $scopedCases |
    Where-Object { -not [string]::IsNullOrWhiteSpace((Get-RepeatGroup -Case $_)) } |
    Group-Object -Property repeat_group |
    Sort-Object -Property Name |
    ForEach-Object {
      $groupCases = @($_.Group)
      $categories = @($groupCases | ForEach-Object { [string]$_.category } | Select-Object -Unique | Sort-Object)

      [pscustomobject]@{
        repeat_group = [string]$_.Name
        categories = $categories
        total_cases = $groupCases.Count
        below_min_size = $groupCases.Count -lt $MinRepeatGroupSize
      }
    }
)

$realRepoCases = @($scopedCases | Where-Object { Test-RealRepoCase -Case $_ })
$realRepoCategories = @($realRepoCases | ForEach-Object { [string]$_.category } | Select-Object -Unique | Sort-Object)
$categoriesBelowMin = @($categoryCoverage | Where-Object { $_.below_min_cases })
$repeatGroupsBelowMin = @($repeatGroupCoverage | Where-Object { $_.below_min_size })
$categoriesWithoutRepeatGroups = @($categoryCoverage | Where-Object { $_.repeat_groups -eq 0 } | Select-Object -ExpandProperty category)

$gates = @(
  [pscustomobject]@{
    name = "min_cases_per_category"
    value = $categoriesBelowMin.Count
    operator = "eq"
    threshold = 0
    passed = $categoriesBelowMin.Count -eq 0
    summary = "categories below $MinCasesPerCategory cases"
  },
  [pscustomobject]@{
    name = "min_repeat_groups"
    value = $repeatGroupCoverage.Count
    operator = "ge"
    threshold = $MinRepeatGroups
    passed = $repeatGroupCoverage.Count -ge $MinRepeatGroups
    summary = "repeat groups available"
  },
  [pscustomobject]@{
    name = "min_repeat_group_size"
    value = $repeatGroupsBelowMin.Count
    operator = "eq"
    threshold = 0
    passed = $repeatGroupsBelowMin.Count -eq 0
    summary = "repeat groups below $MinRepeatGroupSize cases"
  },
  [pscustomobject]@{
    name = "min_real_repo_cases"
    value = $realRepoCases.Count
    operator = "ge"
    threshold = $MinRealRepoCases
    passed = $realRepoCases.Count -ge $MinRealRepoCases
    summary = "real-repo cases available"
  }
)

$warnings = @()
if ($categoriesWithoutRepeatGroups.Count -gt 0) {
  $warnings += "Categories without repeat-group coverage: $($categoriesWithoutRepeatGroups -join ', ')."
}

if ($realRepoCategories.Count -lt 2) {
  $warnings += "Real-repo coverage is concentrated in $($realRepoCategories.Count) categor$(if ($realRepoCategories.Count -eq 1) { 'y' } else { 'ies' })."
}

$recommendedNextCases = @(
  $categoriesWithoutRepeatGroups |
    Sort-Object |
    ForEach-Object {
      [pscustomobject]@{
        category = $_
        recommendation = "Add a three-run repeat_group for this category so token variance can be measured."
      }
    }
)

$failedGates = @($gates | Where-Object { -not $_.passed })
$status = if ($failedGates.Count -eq 0) { "passed" } else { "failed" }

$report = [pscustomobject]@{
  status = $status
  generated_at = (Get-Date).ToString("o")
  scope = $Scope
  cases_path = $resolvedCases.Path
  totals = [pscustomobject]@{
    scoped_cases = $scopedCases.Count
    categories = $categoryCoverage.Count
    repeat_groups = $repeatGroupCoverage.Count
    real_repo_cases = $realRepoCases.Count
    real_repo_categories = $realRepoCategories.Count
    categories_below_min = $categoriesBelowMin.Count
    repeat_groups_below_min = $repeatGroupsBelowMin.Count
    categories_without_repeat_groups = $categoriesWithoutRepeatGroups.Count
  }
  thresholds = [pscustomobject]@{
    min_cases_per_category = $MinCasesPerCategory
    min_repeat_groups = $MinRepeatGroups
    min_repeat_group_size = $MinRepeatGroupSize
    min_real_repo_cases = $MinRealRepoCases
  }
  gates = $gates
  category_coverage = $categoryCoverage
  repeat_group_coverage = $repeatGroupCoverage
  real_repo_categories = $realRepoCategories
  warnings = $warnings
  recommended_next_cases = $recommendedNextCases
}

$targetDir = Split-Path -Parent $target
if (-not (Test-Path -LiteralPath $targetDir)) {
  New-Item -ItemType Directory -Path $targetDir | Out-Null
}

$markdownDir = Split-Path -Parent $markdownTarget
if (-not (Test-Path -LiteralPath $markdownDir)) {
  New-Item -ItemType Directory -Path $markdownDir | Out-Null
}

$lines = [System.Collections.Generic.List[string]]::new()
Add-Line $lines "# Coverage Gap Audit"
Add-Line $lines
Add-Line $lines "- Status: **$status**"
Add-Line $lines "- Scope: $Scope"
Add-Line $lines "- Generated at: $($report.generated_at)"
Add-Line $lines "- Cases: $($resolvedCases.Path)"
Add-Line $lines
Add-Line $lines "## Gates"
Add-Line $lines
Add-Line $lines "| Gate | Value | Threshold | Status |"
Add-Line $lines "| --- | ---: | ---: | --- |"
foreach ($gate in $gates) {
  $gateStatus = if ($gate.passed) { "passed" } else { "failed" }
  Add-Line $lines "| $($gate.name) | $($gate.value) | $($gate.operator) $($gate.threshold) | $gateStatus |"
}
Add-Line $lines
Add-Line $lines "## Category Coverage"
Add-Line $lines
Add-Line $lines "| Category | Cases | Real repo | Repeat-group cases | Repeat groups | Below min |"
Add-Line $lines "| --- | ---: | ---: | ---: | ---: | --- |"
foreach ($category in $categoryCoverage) {
  Add-Line $lines "| $($category.category) | $($category.total_cases) | $($category.real_repo_cases) | $($category.repeat_group_cases) | $($category.repeat_groups) | $($category.below_min_cases) |"
}
Add-Line $lines
Add-Line $lines "## Repeat Groups"
Add-Line $lines
Add-Line $lines "| Repeat group | Categories | Cases | Below min |"
Add-Line $lines "| --- | --- | ---: | --- |"
foreach ($group in $repeatGroupCoverage) {
  Add-Line $lines "| $($group.repeat_group) | $(@($group.categories) -join ', ') | $($group.total_cases) | $($group.below_min_size) |"
}
Add-Line $lines
Add-Line $lines "## Warnings"
if ($warnings.Count -eq 0) {
  Add-Line $lines
  Add-Line $lines "- None."
} else {
  Add-Line $lines
  foreach ($warning in $warnings) {
    Add-Line $lines "- $warning"
  }
}
Add-Line $lines
Add-Line $lines "## Recommended Next Cases"
if ($recommendedNextCases.Count -eq 0) {
  Add-Line $lines
  Add-Line $lines "- None."
} else {
  Add-Line $lines
  foreach ($item in $recommendedNextCases) {
    Add-Line $lines "- $($item.category): $($item.recommendation)"
  }
}

$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $target
Set-Content -LiteralPath $markdownTarget -Value ($lines -join [Environment]::NewLine)
$report | ConvertTo-Json -Depth 12

if ($failedGates.Count -gt 0) {
  exit 1
}
