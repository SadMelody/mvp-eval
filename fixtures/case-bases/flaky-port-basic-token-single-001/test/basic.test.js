import test from "node:test";
import assert from "node:assert/strict";
import {serviceState} from "../index.js";

test("reports the service as available", () => {
  assert.equal(serviceState(), "available");
});
