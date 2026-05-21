import test from "node:test";
import assert from "node:assert/strict";
import {compact} from "../index.js";

test("removes only nullish entries", () => {
  assert.deepEqual(compact([0, null, "ready", undefined, false]), [0, "ready", false]);
});
