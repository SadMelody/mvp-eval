import test from "node:test";
import assert from "node:assert/strict";
import {label} from "../index.js";

test("labels a value", () => {
  assert.equal(label("ready"), "label:ready");
});
