# MVP Token Evaluation

[![MVP token suite](https://github.com/SadMelody/mvp-eval/actions/workflows/mvp-token-suite.yml/badge.svg)](https://github.com/SadMelody/mvp-eval/actions/workflows/mvp-token-suite.yml)

This folder defines a lightweight benchmark loop for measuring Agent token cost on npm repair tasks.

The main MVP question is token behavior:

- How many input tokens does a task consume?
- How many output tokens does it consume?
- How many total tokens does it consume?
- How many tool calls are needed?
- How long does the run take?
- Did the run still produce a valid repair?

Functional success is a gate. Token metrics are the product signal.

## Quick Start

Requirements:

- PowerShell 5.1+ or PowerShell 7+
- Git
- Node.js and npm
- Codex CLI only when running live Agent benchmark or smoke tests

After cloning the repository, run the no-token environment check:

```powershell
.\scripts\setup.ps1
```

Then run the low-cost verification suite:

```powershell
.\scripts\verify-mvp-token-suite.ps1
```

The default suite validates the harness, committed results, coverage, token summaries, and script syntax. It does not run a live Agent and does not consume token budget.

## Flow

1. Add or clone one fixture repository per case.
2. Fill the case in `cases.json`.
3. Generate the exact Agent prompt from the case.
4. Start an Agent run using the generated prompt.
5. The external runner records real `runner_metrics`.
6. Save the Agent's final JSON to `results/<run_id>.json`.
7. Inject the runner metrics into that result JSON.
8. Run `scripts/validate-run.ps1 -RequireRunnerMetrics` against the repo and report.
9. Run `scripts/summarize-token-results.ps1` across `results/`.

For the common single-case path, use `run-codex-case.ps1` with `-Validate` and `-RefreshSummary` so the case report, validator, and token README snapshot update in one command:

```powershell
.\scripts\run-codex-case.ps1 `
  -CasesPath .\cases.json `
  -RunId <case-id> `
  -TemplatePath .\agent-task-template.single-tool.md `
  -Validate `
  -RefreshSummary
```

For a repeated live token benchmark, preview the selected work without spending tokens:

```powershell
.\scripts\run-live-benchmark.ps1 `
  -RunId unit-bug-basic-token-single-001 `
  -Repeat 3 `
  -PlanOnly
```

Execute the previewed benchmark only when accepting live token spend:

```powershell
.\scripts\run-live-benchmark.ps1 `
  -RunId unit-bug-basic-token-single-001 `
  -Repeat 3 `
  -Model <model> `
  -ConfirmTokenSpend
```

The live benchmark resets only the selected fixture before each run, extracts real metrics from Codex events, validates each result, and stores isolated output under `live-runs/<timestamp>/` with `manifest.json` and `summary.json`. It never updates canonical `results/` or the README token snapshot. Use `-RepeatGroup <name>` for existing grouped samples; batches above ten runs require `-AllowLargeBatch`.

For a real end-to-end smoke test that uses a temporary fixture clone and keeps smoke output out of the canonical `results/` folder:

```powershell
.\scripts\test-run-codex-case-smoke.ps1
```

For an opt-in live smoke test against a temporary clean export of the real `escape-string-regexp` repository:

```powershell
.\scripts\test-run-codex-realrepo-smoke.ps1
```

This uses `git archive HEAD`, installs dependencies in a temp directory, runs the Agent through `run-codex-case.ps1`, injects runner metrics from Codex JSON events, and validates the resulting report. It consumes live token budget and keeps output out of the canonical `results/` folder.

Do not ask the Agent to estimate tokens. Token fields must come from the runner, API usage metadata, or the surrounding harness.

`run-codex-case.ps1` extracts token metrics from Codex JSON event output with:

```powershell
.\scripts\extract-runner-metrics.ps1 `
  -EventPath .\runs\<case-id>\codex-events.jsonl `
  -DurationSeconds 180.5 `
  -Model gpt-5.5
```

The extraction rule is covered by:

```powershell
.\scripts\test-extract-runner-metrics.ps1
```

## Generate A Prompt

```powershell
.\scripts\new-agent-prompt.ps1 `
  -CasesPath .\cases.json `
  -RunId escape-string-regexp-001 `
  -OutputPath .\prompts\escape-string-regexp-001.md
```

Feed the generated prompt to the Agent runner. The runner should store the final Agent JSON at `results/<run_id>.json`.

## Inject Runner Metrics

From a metrics JSON file:

```powershell
.\scripts\set-runner-metrics.ps1 `
  -ReportPath .\results\escape-string-regexp-001.json `
  -MetricsPath .\runner-metrics.example.json
```

Or directly from runner parameters:

```powershell
.\scripts\set-runner-metrics.ps1 `
  -ReportPath .\results\escape-string-regexp-001.json `
  -Model gpt-5.5 `
  -InputTokens 10000 `
  -OutputTokens 2000 `
  -ToolCalls 12 `
  -DurationSeconds 180.5
```

## Validation Command

```powershell
.\scripts\validate-run.ps1 `
  -RepoPath ..\escape-string-regexp `
  -ReportPath .\results\escape-string-regexp-001.json `
  -RunId escape-string-regexp-001 `
  -Repo escape-string-regexp `
  -CasesPath .\cases.json `
  -RequireRunnerMetrics
```

The validator checks:

- report JSON shape and required fields
- whether runner token metrics are present when `-RequireRunnerMetrics` is used
- whether the run is within the case's token, tool-call, and duration budget
- `run_id`, `repo`, and task value
- whether `npm test` currently passes
- whether reported changed files match `git diff --name-only`, excluding case-declared pre-existing dirty files
- whether runtime, test, and dependency change flags match the diff
- case-level expected overrides for dependency changes or risk score, when the category intentionally exercises package/dependency tooling
- case-level preservation checks for files that must survive dirty-worktree runs
- whether risk score is consistent with the basic MVP rules

The negative validator self-test currently covers:

- extra fields, missing nested fields, and strict schema field sets
- invalid command and risk enum values
- inconsistent `total_tokens` versus `input_tokens + output_tokens`
- missing required runner metrics under `-RequireRunnerMetrics`
- missing reported passing `npm test` command
- invalid JSON reports
- token, tool-call, and duration budget overruns in `validate-run.ps1`
- budget-ratio gate failures in `check-mvp-pass-bar.ps1`
- actual test file edits that are missing from `changed_files` and forbidden by case policy
- actual dependency lockfile edits that are missing from `changed_files` and forbidden by case policy

Do not rely on local app state files such as `.omx/metrics.json` unless they contain real usage telemetry for the run being evaluated. Treat missing or zero token counts as unavailable telemetry, not as measured usage.

## Token Summary Command

```powershell
.\scripts\summarize-token-results.ps1 -ResultsDir .\results
```

To refresh the README snapshot after new runs:

```powershell
.\scripts\update-readme-summary.ps1
```

To refresh the README snapshot and run the summary sanity checks:

```powershell
.\scripts\refresh-token-summary.ps1
```

To analyze token hotspots, budget-ratio pressure, slow runs, and non-MVP results:

```powershell
.\scripts\analyze-token-anomalies.ps1
```

The analyzer defaults to `-Scope mvp`; use `-Scope all` when you want legacy exploratory runs included, and `-Top 5` or another value to tune the ranked lists.

To run the current MVP token verification suite end to end:

```powershell
.\scripts\verify-mvp-token-suite.ps1
```

This runs the negative validator self-test, schema alignment self-test, runner metrics extraction self-test, live benchmark plan/safety-gate self-test, README summary refresh, result scope audit, coverage gap audit, scoped report validation, pass-bar check, anomaly analysis, repeat-group stability export, and PowerShell syntax checks. It defaults to `-Scope mvp`; `-Scope all` intentionally includes legacy exploratory runs that may exceed current MVP token budgets.

The GitHub Actions workflow at `.github/workflows/mvp-token-suite.yml` runs this same low-cost suite on push, pull request, and manual dispatch. It does not run `-IncludeSmoke`, `-IncludeRealRepoSmoke`, or live benchmark execution.

To include the real Codex Agent smoke test in the same verification entry point:

```powershell
.\scripts\verify-mvp-token-suite.ps1 -IncludeSmoke
```

`-IncludeSmoke` runs the fixture smoke test. To include the real-repo smoke test in the same verification entry point:

```powershell
.\scripts\verify-mvp-token-suite.ps1 -IncludeRealRepoSmoke
```

Both smoke switches are intentionally opt-in because they perform real Agent runs and consume live token budget.

To save a verification result for reuse:

```powershell
.\scripts\verify-mvp-token-suite.ps1 -IncludeRealRepoSmoke -OutputPath .\verification-realrepo-smoke.json
```

To export a single evidence artifact for handoff or archival:

```powershell
.\scripts\export-mvp-evidence.ps1
```

This writes `mvp-evidence.json` with the verification suite result, pass bar, scope audit, coverage gap audit, token anomaly analysis, and headline token metrics. Use `-IncludeSmoke` when the evidence artifact should also include a fresh fixture Agent smoke run, and `-IncludeRealRepoSmoke` when it should also include a fresh real-repo Agent smoke run. To avoid rerunning a smoke test that already completed, pass the saved verification result:

```powershell
.\scripts\export-mvp-evidence.ps1 -VerificationPath .\verification-realrepo-smoke.json
```

To generate a human-readable readiness report from the evidence artifact:

```powershell
.\scripts\export-mvp-readiness.ps1
```

This writes `MVP_READINESS.md`.

To export repeat-group token stability evidence:

```powershell
.\scripts\export-token-stability.ps1
```

This writes `token-stability.json` and `TOKEN_STABILITY.md`, and fails if repeat-group token range exceeds the configured stability threshold.

To audit MVP case coverage gaps before adding more runs:

```powershell
.\scripts\audit-coverage-gaps.ps1
```

This writes `coverage-gaps.json` and `COVERAGE_GAPS.md`. The audit gates minimum category coverage, repeat-group count, repeat-group size, and real-repo coverage, then reports advisory gaps such as categories that still need repeat-group samples.

To audit that MVP, expected-failure, and legacy results are separated correctly:

```powershell
.\scripts\audit-result-scopes.ps1
```

This requires all MVP runs to pass, all expected-failure runs to match their configured non-passing status, and legacy runs to fail only for explicitly allowed historical reasons such as token-budget overruns or missing runner metrics.

To verify the validator rejects bad reports and forbidden edits:

```powershell
.\scripts\test-validate-run-negative.ps1
```

To verify `validate-run.ps1` stays behaviorally aligned with `evaluation.schema.json`:

```powershell
.\scripts\test-validator-schema-alignment.ps1
```

To revalidate every report in the current MVP scope against its case repo:

```powershell
.\scripts\validate-all-results.ps1 -NoExitOnFailure
```

This runs `validate-run.ps1` for each scoped report and therefore re-runs each case repo's `npm test`. The default scope is `mvp`; use `-Scope all -NoExitOnFailure` for the historical whole-set view. Omit `-NoExitOnFailure` when you want CI-style nonzero exit on any failed report.

To check the current result set against the MVP pass bar:

```powershell
.\scripts\check-mvp-pass-bar.ps1
```

The pass-bar checker defaults to `-Scope mvp`, which excludes legacy exploratory runs, expected-failure samples, and template placeholders. Use `-Scope all -NoExitOnFailure` when you intentionally want the historical whole-set view.

This reports:

- total runs
- functionally passed runs
- token/tool/duration budget-passed runs
- MVP-passed runs, meaning `agent_report.status = passed` and all configured budgets passed
- expected-failure validated runs, meaning a configured non-passing `expected_status` matched and all configured budgets passed
- failure reason counts, such as `total_token_budget_failed`, `functional_status_failed`, `expected_status_failed`, and `missing_runner_metrics`
- category-level summaries grouped by `cases.json` category
- scope-level summaries grouped by `cases.json` scope
- repeat-group summaries grouped by `cases.json` repeat_group, including token range and pass rate
- total input/output/overall tokens
- average, median, and P90 token usage
- average tool calls and duration
- highest-token run

Current summary snapshot:

- reports with metrics: 42 of 43
- MVP-passed reports: 32
- expected-failure validated reports: 4
- median total tokens across metric runs: 72593
- P90 total tokens across metric runs: 258409.8
- median total tokens for MVP-passed runs: 72563.5
- P90 total tokens for MVP-passed runs: 72927.1
- main non-budget failure reasons: `expected_status_failed` with 4 validated expected-failure runs

Current category snapshot:

- `dependency-tooling`: metric runs 4/4; MVP 4/4; median 72461; P90 72764.2.
- `dirty-worktree`: metric runs 3/3; MVP 3/3; median 72547; P90 72573.4.
- `failure-path`: metric runs 4/4; MVP 0/4; median 71241.5; P90 71336.1; expected-failure validated 4.
- `flaky-test`: metric runs 3/3; MVP 3/3; median 72123; P90 72127.
- `lint`: metric runs 3/3; MVP 3/3; median 71898; P90 72029.2.
- `script-config`: metric runs 3/3; MVP 3/3; median 72818; P90 72884.4.
- `script-config-open-ended`: metric runs 1/1; MVP 0/1; median 298625; P90 298625.
- `typecheck-tooling`: metric runs 8/8; MVP 8/8; median 72855; P90 73191.
- `typecheck-tooling-open-ended`: metric runs 4/5; MVP 0/4; median 314579.5; P90 411005.4.
- `unit-test`: metric runs 3/3; MVP 3/3; median 72437; P90 72469.
- `unit-test-real-repo`: metric runs 6/6; MVP 5/6; median 72642.5; P90 167852.5.

Current scope snapshot:

- `expected-failure`: metric runs 4/4; MVP 0/4; functional pass rate 0; median 71241.5; P90 71336.1; expected-failure validated 4.
- `legacy`: metric runs 6/7; MVP 0/6; functional pass rate 1; median 287240.5; P90 394519.
- `mvp`: metric runs 32/32; MVP 32/32; functional pass rate 1; median 72563.5; P90 72927.1.

Current repeat snapshot:

- `dependency-tooling-package-config-token-single`: metric runs 3/3; MVP 3/3; range 72081-72606; delta 525 tokens; delta pct 0.7258%; median 72316; P90 72548.
- `dirty-worktree-preservation-token-single`: metric runs 3/3; MVP 3/3; range 72329-72580; delta 251 tokens; delta pct 0.3463%; median 72547; P90 72573.4.
- `flaky-transient-retry-token-single`: metric runs 3/3; MVP 3/3; range 71995-72128; delta 133 tokens; delta pct 0.1845%; median 72123; P90 72127.
- `is-plain-obj-unit-token-single`: metric runs 3/3; MVP 3/3; range 72468-72677; delta 209 tokens; delta pct 0.2879%; median 72667; P90 72675.
- `lint-format-runtime-token-single`: metric runs 3/3; MVP 3/3; range 71854-72062; delta 208 tokens; delta pct 0.2891%; median 71898; P90 72029.2.
- `script-config-package-script-token-single`: metric runs 3/3; MVP 3/3; range 72424-72901; delta 477 tokens; delta pct 0.656%; median 72818; P90 72884.4.
- `type-declaration-path-basic-token-single`: metric runs 3/3; MVP 3/3; range 72654-72703; delta 49 tokens; delta pct 0.0674%; median 72686; P90 72699.6.
- `unit-test-runtime-fix-token-single`: metric runs 3/3; MVP 3/3; range 72124-72477; delta 353 tokens; delta pct 0.4879%; median 72437; P90 72469.

Current escape-string-regexp token baseline:

- `escape-string-regexp-token-001`: functional repair passed, but exceeded the 120000 total-token budget.
- `escape-string-regexp-token-strict-001`: functional repair passed with fewer tool calls, but still exceeded the token budget.
- `escape-string-regexp-token-single-002`: functional repair passed and stayed within token, tool-call, and duration budgets.

Current local fixture baselines:

- `dependency-tooling-basic-token-single-001`: local dependency path configuration repair passed and stayed within all budgets.
- `dependency-script-basic-token-single-001`: package test script configuration repair passed and stayed within all budgets.
- `dependency-module-type-basic-token-single-001`: package ESM module type configuration repair passed and stayed within all budgets.
- `dependency-module-type-commonjs-basic-token-single-001`: explicit CommonJS/ESM module type mismatch repair passed and stayed within all budgets.
- `dependency-tooling` category: 4/4 MVP-passed; median total tokens 72461; P90 total tokens 72764.2.
- `dirty-worktree-basic-token-single-001`: runtime repair passed while preserving the pre-existing dirty `README.md` content and hash.
- `dirty-notes-basic-token-single-001`: runtime repair passed while preserving the pre-existing dirty `NOTES.md` content and hash.
- `dirty-same-file-basic-token-single-001`: same-file runtime repair passed while preserving the pre-existing dirty `index.js` marker.
- `dirty-worktree` category: 3/3 MVP-passed; median total tokens 72547; P90 total tokens 72573.4.
- `flaky-once-basic-token-single-001`: transient first-run failure passed by rerunning `npm test`, with no tracked file changes.
- `flaky-cache-warm-basic-token-single-001`: transient cache warm-up failure passed by rerunning `npm test`, with no tracked file changes.
- `flaky-port-basic-token-single-001`: transient port contention failure passed by rerunning `npm test`, with no tracked file changes.
- `flaky-test` category: 3/3 MVP-passed; median total tokens 72123; P90 total tokens 72127.
- `failure-runtime-disallowed-basic-token-single-001`: expected-failure path passed validation by reporting `failed`, leaving the worktree clean, and staying within all budgets.
- `failure-missing-export-disallowed-basic-token-single-001`: expected-failure path passed validation for a missing runtime export while leaving the worktree clean.
- `failure-async-disallowed-basic-token-single-001`: expected-failure path passed validation for an async assertion mismatch while leaving the worktree clean.
- `failure-test-disallowed-basic-token-single-001`: expected-failure path passed validation for an incorrect test expectation while leaving runtime and test files unchanged.
- `failure-path` category: 4 expected-failure samples retained separately; 0/4 MVP-passed by design; 4/4 expected-failure validated; median total tokens 71241.5; P90 total tokens 71338.1.
- `lint-basic-token-single-001`: lint-only semicolon formatting repair passed and stayed within all budgets.
- `lint-quote-basic-token-single-001`: lint-only quote style repair passed and stayed within all budgets.
- `lint-var-basic-token-single-001`: lint-only `var` to `const` style repair passed and stayed within all budgets.
- `lint` category: 3/3 MVP-passed; median total tokens 71898; P90 total tokens 72029.2.
- `script-path-config-token-001`: functional repair passed, but exceeded the token budget in open-ended mode; tracked under `script-config-open-ended`.
- `script-path-config-token-single-001`: configuration-only repair passed and stayed within all budgets.
- `script-glob-config-token-single-001`: test script glob repair passed and stayed within all budgets.
- `script-spec-config-token-single-001`: test script directory repair passed and stayed within all budgets.
- `script-config` category: 3/3 MVP-passed; median total tokens 72818; P90 total tokens 72884.4.
- `script-config-open-ended` category: 1 exploratory run retained separately; median total tokens 298625; P90 total tokens 298625.
- `type-declaration-path-basic-token-single-001`: package declaration entry repair passed and stayed within all budgets.
- `type-declaration-path-basic-token-single-001..003`: repeated package declaration entry repairs passed 3/3; total tokens ranged from 72654 to 72703, a 49-token range or 0.0674% of average.
- `type-export-condition-basic-token-single-001`: package exports types condition repair passed and stayed within all budgets.
- `type-export-import-basic-token-single-001`: package exports import entry repair passed and stayed within all budgets.
- `type-export-default-basic-token-single-001`: package exports default entry repair passed and stayed within all budgets.
- `typecheck-tooling` category: 7/8 MVP-passed; median total tokens 72855; P90 total tokens 73191; MVP-passed median total tokens 72780; MVP-passed P90 total tokens 73231.
- `typecheck-tooling-open-ended` category: 5 legacy exploratory runs retained separately; 0/5 MVP-passed; median total tokens 314579.5; P90 total tokens 411005.4.
- `unit-bug-basic-token-single-001`: small runtime repair passed and stayed within all budgets.
- `unit-array-compact-basic-token-single-001`: small runtime repair passed and stayed within all budgets.
- `unit-string-trim-basic-token-single-001`: small runtime repair passed and stayed within all budgets.
- `unit-test` category: 3/3 MVP-passed; median total tokens 72437; P90 total tokens 72469.

Current real-repo baselines:

- `is-plain-obj-unit-token-001`: real npm repo runtime repair passed with a clean `index.js` diff, but exceeded the token budget in open-ended mode.
- `is-plain-obj-unit-token-single-001`: same real npm repo repair passed within budget under the single-tool path.
- `is-plain-obj-unit-token-single-001..003`: repeated single-tool real-repo runs passed 3/3; total tokens ranged from 72468 to 72677, a 209-token range or 0.2879% of average.
- `escape-string-regexp-unit-token-single-001`: real npm repo runtime repair passed within budget by restoring hyphen escaping in `index.js`; total tokens 72618, 1 tool call, 167.09 seconds.
- `arrify-unit-token-single-001`: real npm package runtime repair passed within budget by restoring iterable expansion in `index.js`; total tokens 72497, 1 tool call, 141.15 seconds.

## Fixture Categories

Use at least three samples per category before trusting the MVP signal:

- `lint`: style or lint-only failures
- `typecheck-tooling`: TypeScript, declaration, or package exports tooling failures
- `unit-test`: real behavior bug exposed by tests
- `dependency-tooling`: package manager or test tool incompatibility
- `flaky-test`: nondeterministic test handling
- `dirty-worktree`: existing user edits that must not be reverted
- `failure-path`: expected-failure samples that should report failure without unsafe edits

## MVP Pass Bar

- Metrics capture rate: 95% or higher
- JSON schema compliance: 95% or higher
- Functional pass rate: 70% or higher
- Median total tokens under the chosen MVP budget
- P90 total tokens under the chosen MVP budget
- No forbidden edits: 90% or higher
- Full verification execution: 95% or higher

Set the token budget in `cases.json` per category. Early defaults are intentionally placeholders until you collect enough baseline runs.
