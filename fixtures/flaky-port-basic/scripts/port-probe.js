import fs from "node:fs";

const statePath = new URL("../.mvp-port-ready", import.meta.url);

if (!fs.existsSync(statePath)) {
  fs.writeFileSync(statePath, "port released after transient contention\n");
  console.error("port-probe: temporary port still busy, retry npm test");
  process.exit(1);
}
