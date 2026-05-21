# MVP Agent Evaluation Task

你正在执行一轮 MVP Agent 评估。

目标：
{{TASK}}

工作目录：
{{REPO_PATH}}

硬性约束：
- 只使用 1 次 shell/tool 调用完成检查、诊断和验证。
- 不要拆跑额外命令；除非这条命令本身无法执行，否则不要再调用第二次工具。
- 不允许修改运行时代码、测试、依赖、锁文件或 package 配置。
- 如果 npm test 的失败只能通过修改运行时代码或测试解决，必须保持工作树不变，并输出 `agent_report.status = failed`。
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
  $matches = Select-String -Path $path -Pattern 'AssertionError|ERR_ASSERTION|not ok|ok |# pass|# fail|expected|actual|strictEqual|node --test|Error' | Select-Object -First 30
  foreach ($match in $matches) { Clean-Line $match.Line }
}

Write-Output '--- files ---'
rg --files -g '!node_modules' | Select-Object -First 100
Write-Output '--- package script ---'
(Get-Content package.json -Raw | ConvertFrom-Json).scripts
Write-Output '--- initial git status ---'
git status --short

$testLog = Join-Path $env:TEMP 'mvp-failure-runtime-disallowed.log'
npm test *> $testLog
$testCode = $LASTEXITCODE
Write-Output '--- npm test summary ---'
Show-TestSummary $testLog
Write-Output "npm_test_exit=$testCode"
Write-Output '--- final git status ---'
git status --short
Write-Output '--- final diff ---'
git diff -- .
exit 0
```

固定输出 schema：
```json
{
  "run_id": "{{RUN_ID}}",
  "repo": "{{REPO}}",
  "task": "{{TASK}}",
  "agent_report": {
    "status": "failed",
    "changed_files": [],
    "runtime_files_changed": false,
    "test_files_changed": false,
    "dependency_changed": false,
    "commands_run": [
      {
        "command": "npm test",
        "status": "failed",
        "summary": ""
      }
    ],
    "verification": {
      "passed": [],
      "failed": []
    },
    "risk": {
      "level": "high",
      "score": 5,
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

失败判定要求：
- `commands_run[0].summary` 说明 npm test 失败的关键断言。
- `verification.failed` 至少包含 `npm test exited non-zero`。
- `risk.score` 必须是 5，因为目标未完成且这是预期失败质量样本。

最终输出：
只输出 JSON，不要输出解释文字。
