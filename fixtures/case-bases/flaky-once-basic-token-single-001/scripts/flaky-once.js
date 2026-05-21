import fs from "node:fs";

const statePath = new URL("../.mvp-flaky-state", import.meta.url);

if (!fs.existsSync(statePath)) {
  fs.writeFileSync(statePath, "transient failure observed\n");
  console.error("flaky-once: transient setup race, retry npm test");
  process.exit(1);
}
