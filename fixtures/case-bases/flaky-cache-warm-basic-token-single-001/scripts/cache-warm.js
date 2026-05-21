import fs from "node:fs";

const statePath = new URL("../.mvp-cache-ready", import.meta.url);

if (!fs.existsSync(statePath)) {
  fs.writeFileSync(statePath, "cache warmed after transient miss\n");
  console.error("cache-warm: dependency cache still warming, retry npm test");
  process.exit(1);
}
