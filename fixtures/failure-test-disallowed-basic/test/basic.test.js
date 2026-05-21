import test from "node:test";
import assert from "node:assert/strict";
import {double} from "../index.js";

test("doubles a number", () => {
  assert.equal(double(2), 5);
});
