# Contributing

This project measures Agent token behavior on npm repair tasks. Functional repair is a gate; token metrics are the product signal.

## Local Checks

Run the no-token setup check first:

```powershell
.\scripts\setup.ps1
```

Then run the low-cost verification suite:

```powershell
.\scripts\verify-mvp-token-suite.ps1
```

Do not run live Agent smoke tests in routine pull requests. `-IncludeSmoke` and `-IncludeRealRepoSmoke` are opt-in because they execute a real Agent run and consume token budget.

## Adding A Case

1. Add a case entry to `cases.json`.
2. Add or update fixture data under `fixtures/` when the case does not use an external repository.
3. Run the Agent through the generated prompt and save the final JSON report under `results/<run_id>.json`.
4. Inject real runner metrics from Codex/API usage data. Do not ask the Agent to estimate token counts.
5. Run `.\scripts\verify-mvp-token-suite.ps1`.

## Data Hygiene

Do not commit raw Agent event logs, generated prompts, temporary repositories, local `.omx` state, secrets, or machine-specific evidence exports. The `.gitignore` is intentionally strict for those artifacts.

Keep committed result reports scoped to sanitized benchmark outputs that are useful for validating the harness.
