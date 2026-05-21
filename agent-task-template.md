# MVP Agent Evaluation Task

你正在执行一轮 MVP Agent 评估。

目标：
{{TASK}}

工作目录：
{{REPO_PATH}}

约束：
- 先阅读项目结构、package scripts、测试配置和当前 git 状态。
- 优先最小 diff。
- 不要跳过 lint、typecheck 或测试。
- 不要删除测试。
- 不要修改运行时逻辑，除非证明无法避免。
- 不要估算 token；runner_metrics 由外部系统填写。
- 完成后只输出符合 evaluation.schema.json 的 JSON。

Token 预算约束：
- 测试必须真实执行，但命令输出必须保持简短。
- 最多使用 4 次 shell/tool 调用完成任务。优先把读取上下文、诊断、验证合并成少量命令。
- 不要运行会展开完整对象或递归输出依赖目录的命令，例如裸 `Get-ChildItem -Force`、`dir /s`、`npm test` 直接输出海量日志。
- 查看项目结构时使用 `rg --files -g '!node_modules'` 或 `Get-ChildItem -Force | Select-Object Mode,Length,Name`。
- 不要单独拆跑 `npx xo`、`npx ava`、`npx tsd` 来替代最终验证；必须至少运行一次完整 `npm test`，修复后再运行一次完整 `npm test`。
- 运行测试时把完整日志重定向到临时目录，不要用 `Tee-Object` 把完整日志送回上下文。只输出清洗后的摘要，例如：
  `$log = Join-Path $env:TEMP 'mvp-npm-test.log'; npm test *> $log; $code = $LASTEXITCODE; if ($code -eq 0) { Get-Content $log -Tail 40 } else { Select-String -Path $log -Pattern 'tsd|@types/node|TypeScript|error TS|Cannot find|Property .* does not exist' | Select-Object -First 20 | ForEach-Object { ($_.Line -replace '\x1b\[[0-9;]*m','' -replace '\s{2,}',' ').Trim() } }; exit $code`
- 测试失败后，优先用 `Select-String` 从临时日志中提取 `error TS`、`@types/node`、`tsd`、`TypeScript` 等关键词，不要把完整日志贴回上下文。
- 如果失败原因是 tsd 加载了无关的 ambient `@types/*` 声明，优先做 tsd 配置级修复，不要改运行时代码、测试或依赖锁文件。
- 最终报告可以概括命令结果，不需要复制完整测试输出。

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
