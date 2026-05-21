import test from "node:test";
import assert from "node:assert/strict";
import {normalizeName} from "../index.js";

test("normalizes surrounding whitespace and case", () => {
  assert.equal(normalizeName(" Ada "), "ada");
});
