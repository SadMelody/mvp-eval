import fs from "node:fs";

const source = fs.readFileSync(new URL("../index.js", import.meta.url), "utf8");

if (source.includes(";")) {
  console.error("lint-basic: semicolons are not allowed in index.js");
  process.exitCode = 1;
}
