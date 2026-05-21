import fs from "node:fs";

const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"));
const importExport = packageJson.exports?.["."]?.import;

if (!importExport || !fs.existsSync(importExport)) {
  console.error(`exports.import does not point to an existing runtime file: ${importExport}`);
  process.exit(1);
}
