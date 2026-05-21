import test from "node:test";
import assert from "node:assert/strict";
import {triple} from "../index.js";

test("triples values", () => {
  assert.equal(triple(4), 12);
});
