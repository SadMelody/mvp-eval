import fs from "node:fs";

const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"));
const typeExport = packageJson.exports?.["."]?.types;

if (!typeExport || !fs.existsSync(typeExport)) {
  console.error(`exports.types does not point to an existing declaration file: ${typeExport}`);
  process.exit(1);
}
