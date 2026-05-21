import test from "node:test";
import assert from "node:assert/strict";
import {answer} from "../index.js";

test("returns the answer", () => {
  assert.equal(answer(), 42);
});
