import fs from "node:fs";
import path from "node:path";

const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"));
const specifier = packageJson.devDependencies?.["@mvp/local-runner"];
const expected = "file:./vendor/mvp-local-runner";

if (specifier !== expected) {
  console.error(`dependency config error: expected @mvp/local-runner to use ${expected}, got ${specifier}`);
  process.exit(1);
}

const target = path.resolve(specifier.replace(/^file:/, ""));
if (!fs.existsSync(target)) {
  console.error(`dependency config error: local dependency path does not exist: ${target}`);
  process.exit(1);
}
