import test from "node:test";
import assert from "node:assert/strict";
import {slugify} from "../index.js";

test("slugifies spaces", () => {
  assert.equal(slugify("Hello World"), "hello-world");
});
