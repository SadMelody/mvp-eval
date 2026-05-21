import fs from "node:fs";

const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"));
const typesPath = packageJson.types;

if (!typesPath || !fs.existsSync(typesPath)) {
  console.error(`types entry does not point to an existing declaration file: ${typesPath}`);
  process.exit(1);
}
