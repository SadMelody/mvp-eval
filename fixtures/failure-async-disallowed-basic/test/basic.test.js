import test from "node:test";
import assert from "node:assert/strict";
import {fetchValue} from "../index.js";

test("fetches the expected value", async () => {
  assert.equal(await fetchValue(), 8);
});
