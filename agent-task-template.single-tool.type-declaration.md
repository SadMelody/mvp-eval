# MVP Agent Evaluation Task

你正在执行一轮 MVP Agent 评估。

目标：
{{TASK}}

工作目录：
{{REPO_PATH}}

硬性约束：
- 只使用 1 次 shell/tool 调用完成检查、诊断、修复和验证。
- 不要拆跑额外命令；除非这条命令本身无法执行，否则不要再调用第二次工具。
- 只允许最小范围 type/declaration/package exports tooling 配置修复。
- 不要修改运行时代码、测试或依赖锁文件。
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
  $matches = Select-String -Path $path -Pattern 'types entry|exports\.types|exports\.import|exports\.default|declaration file|runtime file|not ok|ok |# pass|# fail|node --test|Error' | Select-Object -First 24
  foreach ($match in $matches) { Clean-Line $match.Line }
}

Write-Output '--- files ---'
rg --files -g '!node_modules' | Select-Object -First 100
Write-Output '--- package script and type fields ---'
$pkg = Get-Content package.json -Raw | ConvertFrom-Json
$pkg.scripts
$pkg.types
$pkg.exports
Write-Output '--- initial git status ---'
git status --short

$initialLog = Join-Path $env:TEMP 'mvp-type-declaration-initial.log'
npm test *> $initialLog
$initialCode = $LASTEXITCODE
Write-Output '--- initial npm test summary ---'
Show-TestSummary $initialLog

$changed = $false
if ($initialCode -ne 0 -and (Select-String -Path $initialLog -Pattern 'types entry|exports\.types|exports\.import|exports\.default|declaration file|runtime file' -Quiet)) {
  $json = Get-Content package.json -Raw
  if ($json -match '"types"\s*:\s*"\./dist/index\.d\.ts"') {
    $json = $json -replace '"types"\s*:\s*"\./dist/index\.d\.ts"', '"types": "./index.d.ts"'
    Set-Content -LiteralPath package.json -Value $json -NoNewline
    $changed = $true
  } elseif ($json -match '"types"\s*:\s*"\./missing\.d\.ts"') {
    $json = $json -replace '"types"\s*:\s*"\./missing\.d\.ts"', '"types": "./index.d.ts"'
    Set-Content -LiteralPath package.json -Value $json -NoNewline
    $changed = $true
  } elseif ($json -match '"import"\s*:\s*"\./dist/index\.js"') {
    $json = $json -replace '"import"\s*:\s*"\./dist/index\.js"', '"import": "./index.js"'
    Set-Content -LiteralPath package.json -Value $json -NoNewline
    $changed = $true
  } elseif ($json -match '"default"\s*:\s*"\./dist/index\.js"') {
    $json = $json -replace '"default"\s*:\s*"\./dist/index\.js"', '"default": "./index.js"'
    Set-Content -LiteralPath package.json -Value $json -NoNewline
    $changed = $true
  }
}

$finalLog = Join-Path $env:TEMP 'mvp-type-declaration-final.log'
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

风险评分规则：
- 1：只改配置、文档或测试；运行时无变化；完整验证通过。
- 2：小范围运行时代码改动；有直接测试覆盖；完整验证通过。
- 3：涉及核心逻辑或公共 API；验证通过但影响面中等。
- 4：跨模块、依赖、构建链或架构改动；验证不完整或风险较高。
- 5：失败、跳过关键验证、误改核心逻辑、破坏兼容性或存在不可解释 diff。

最终输出：
只输出 JSON，不要输出解释文字。
