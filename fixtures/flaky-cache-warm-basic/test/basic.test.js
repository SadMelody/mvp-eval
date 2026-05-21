import test from "node:test";
import assert from "node:assert/strict";
import {cachedValue} from "../index.js";

test("returns a warmed cache value", () => {
  assert.equal(cachedValue(), "warm");
});
