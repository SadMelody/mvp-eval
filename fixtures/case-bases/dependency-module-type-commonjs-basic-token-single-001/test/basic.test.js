import test from "node:test";
import assert from "node:assert/strict";
import {double} from "../index.js";

test("doubles values", () => {
  assert.equal(double(4), 8);
});
