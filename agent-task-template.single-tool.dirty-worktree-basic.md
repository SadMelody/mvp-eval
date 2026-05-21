# MVP Agent Evaluation Task

你正在执行一轮 MVP Agent 评估。

目标：
{{TASK}}

工作目录：
{{REPO_PATH}}

硬性约束：
- 只使用 1 次 shell/tool 调用完成检查、诊断、修复和验证。
- 不要拆跑额外命令；除非这条命令本身无法执行，否则不要再调用第二次工具。
- 可以做最小范围运行时代码修复，但不要修改测试或依赖锁文件。
- 当前工作树里可能已经有用户未提交改动；不要覆盖、清理、格式化或回退这些既有改动。
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
  $matches = Select-String -Path $path -Pattern 'ERR_ASSERTION|Expected values|actual:|expected:|not ok|ok |# pass|# fail|node --test' | Select-Object -First 22
  foreach ($match in $matches) { Clean-Line $match.Line }
}

Write-Output '--- files ---'
rg --files -g '!node_modules' | Select-Object -First 80
Write-Output '--- package script ---'
(Get-Content package.json -Raw | ConvertFrom-Json).scripts
Write-Output '--- initial git status ---'
git status --short
Write-Output '--- existing dirty README marker ---'
Select-String -Path README.md -Pattern 'USER DIRTY NOTE' -SimpleMatch

$initialLog = Join-Path $env:TEMP 'mvp-dirty-worktree-initial.log'
npm test *> $initialLog
$initialCode = $LASTEXITCODE
Write-Output '--- initial npm test summary ---'
Show-TestSummary $initialLog

$changed = $false
if ($initialCode -ne 0 -and (Select-String -Path $initialLog -Pattern 'ERR_ASSERTION|Expected values|actual: -1|expected: 5' -Quiet)) {
  $source = Get-Content index.js -Raw
  if ($source -match 'return left - right;') {
    $source = $source -replace 'return left - right;', 'return left + right;'
    Set-Content -LiteralPath index.js -Value $source -NoNewline
    $changed = $true
  }
}

$finalLog = Join-Path $env:TEMP 'mvp-dirty-worktree-final.log'
npm test *> $finalLog
$finalCode = $LASTEXITCODE
Write-Output '--- final npm test summary ---'
Show-TestSummary $finalLog
Write-Output '--- final dirty README marker ---'
Select-String -Path README.md -Pattern 'USER DIRTY NOTE' -SimpleMatch
Write-Output "initial_exit=$initialCode final_exit=$finalCode changed=$changed"
Write-Output '--- final git status ---'
git status --short
Write-Output '--- final runtime diff ---'
git diff -- index.js
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
    "runtime_files_changed": true,
    "test_files_changed": false,
    "dependency_changed": false,
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
      "score": 2,
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

风险评分规则：
- 1：只改配置、文档或测试；运行时无变化；完整验证通过。
- 2：小范围运行时代码改动；有直接测试覆盖；完整验证通过。
- 3：涉及核心逻辑或公共 API；验证通过但影响面中等。
- 4：跨模块、依赖、构建链或架构改动；验证不完整或风险较高。
- 5：失败、跳过关键验证、误改核心逻辑、破坏兼容性或存在不可解释 diff。

最终输出：
只输出 JSON，不要输出解释文字。
