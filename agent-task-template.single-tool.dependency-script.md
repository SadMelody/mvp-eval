# MVP Agent Evaluation Task

你正在执行一轮 MVP Agent 评估。

目标：
{{TASK}}

工作目录：
{{REPO_PATH}}

硬性约束：
- 只使用 1 次 shell/tool 调用完成检查、诊断、修复和验证。
- 不要拆跑额外命令；除非这条命令本身无法执行，否则不要再调用第二次工具。
- 只允许最小范围 package/tooling 配置修复；不要修改运行时代码、测试、依赖锁文件或检查脚本。
- 不要运行 npm install；这个样本只验证 package script 配置。
- 不要估算 token；runner_metrics 由外部系统填写。
- 完成后只输出符合 evaluation.schema.json 的 JSON。

请执行这一条 PowerShell 命令：

```powershell
$ErrorActionPreference = 'Continue'
function Clean-Line($line) {
  (($line -replace "`e\[[0-9;]*m", '') -replace '\s{2,}', ' ').Trim()
}
function Show-TestSummary($path) {
  if (-not (Test-Path -LiteralPath $path)) { return }
  $matches = Select-String -Path $path -Pattern 'missing-package-check|dependency script error|MODULE_NOT_FOUND|not ok|ok |# pass|# fail|node --test|tests? passed|Error' | Select-Object -First 24
  foreach ($match in $matches) { Clean-Line $match.Line }
}

Write-Output '--- files ---'
rg --files -g '!node_modules' | Select-Object -First 100
Write-Output '--- package script ---'
(Get-Content package.json -Raw | ConvertFrom-Json).scripts
Write-Output '--- initial git status ---'
git status --short

$initialLog = Join-Path $env:TEMP 'mvp-dependency-script-initial.log'
npm test *> $initialLog
$initialCode = $LASTEXITCODE
Write-Output '--- initial npm test summary ---'
Show-TestSummary $initialLog

$changed = $false
if ($initialCode -ne 0 -and (Select-String -Path $initialLog -Pattern 'missing-package-check|MODULE_NOT_FOUND' -Quiet)) {
  $packageText = Get-Content package.json -Raw
  if ($packageText -match 'scripts/missing-package-check\.js' -and (Test-Path -LiteralPath 'scripts/check-package-config.js')) {
    $packageText = $packageText -replace 'scripts/missing-package-check\.js', 'scripts/check-package-config.js'
    Set-Content -LiteralPath package.json -Value $packageText -NoNewline
    $changed = $true
  }
}

$finalLog = Join-Path $env:TEMP 'mvp-dependency-script-final.log'
npm test *> $finalLog
$finalCode = $LASTEXITCODE
Write-Output '--- final npm test summary ---'
Show-TestSummary $finalLog
Write-Output "initial_exit=$initialCode final_exit=$finalCode changed=$changed"
Write-Output '--- final git status ---'
git status --short
Write-Output '--- final package diff ---'
git diff -- package.json
exit $finalCode
```

固定输出 schema：
```json
{
  "run_id": "{{RUN_ID}}",
  "repo": "{{REPO}}",
  "task": "{{TASK}}",
  "agent_report": {
    "status": "passed|failed|blocked|partial",
    "changed_files": [],
    "runtime_files_changed": false,
    "test_files_changed": false,
    "dependency_changed": true,
    "commands_run": [
      {
        "command": "npm test",
        "status": "passed|failed",
        "summary": ""
      }
    ],
    "verification": {
      "passed": [],
      "failed": []
    },
    "risk": {
      "level": "low|medium|high",
      "score": 1,
      "reasons": [],
      "remaining_risks": []
    }
  },
  "runner_metrics": {
    "model": null,
    "input_tokens": null,
    "output_tokens": null,
    "total_tokens": null,
    "tool_calls": null,
    "duration_seconds": null
  }
}
```

最终输出：
只输出 JSON，不要输出解释文字。
