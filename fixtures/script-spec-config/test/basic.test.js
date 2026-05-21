import test from "node:test";
import assert from "node:assert/strict";
import {toInitials} from "../index.js";

test("builds initials", () => {
  assert.equal(toInitials("Grace Hopper"), "GH");
});
