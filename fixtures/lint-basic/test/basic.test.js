import test from "node:test";
import assert from "node:assert/strict";
import {label} from "../index.js";

test("formats the value label", () => {
  assert.equal(label("a"), "value:a");
});
