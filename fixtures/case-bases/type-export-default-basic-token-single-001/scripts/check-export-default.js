import fs from "node:fs";

const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"));
const defaultExport = packageJson.exports?.["."]?.default;

if (!defaultExport || !fs.existsSync(defaultExport)) {
  console.error(`exports.default does not point to an existing runtime file: ${defaultExport}`);
  process.exit(1);
}
