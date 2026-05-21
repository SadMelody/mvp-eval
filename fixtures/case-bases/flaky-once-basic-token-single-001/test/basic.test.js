import test from "node:test";
import assert from "node:assert/strict";
import {stableValue} from "../index.js";

test("returns a stable value", () => {
  assert.equal(stableValue(), "ready");
});
