// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Checks that the JSON Schema agrees with the shared examples (examples/).
// The Swift server, the CLI and Emacs use the same examples (in their own conformance tests).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import Ajv2020 from "ajv/dist/2020.js";

const read = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url), "utf8"));
const ajv = new Ajv2020({
  strict: true,
  strictRequired: false,
  allowUnionTypes: true,
  allErrors: true,
});
const validateRequest = ajv.compile(read("../schema/request.schema.json"));
const validateResponse = ajv.compile(read("../schema/response.schema.json"));
const validateLocation = ajv.compile(read("../schema/location.schema.json"));

test("open validation examples: schema pass/fail matches the expectation (ok or error)", () => {
  for (const item of read("../examples/open-validation.json")) {
    const valid = validateRequest(item.request);
    assert.equal(
      valid,
      item.expect === "ok",
      `${item.name}: ${JSON.stringify(validateRequest.errors)}`,
    );
  }
});

test("requests built from the URL examples match the schema", () => {
  for (const item of read("../examples/url.json")) {
    if (!item.request) continue;
    assert.ok(
      validateRequest(item.request),
      `${item.name}: ${JSON.stringify(validateRequest.errors)}`,
    );
  }
});

test("open requires path, ping does not", () => {
  assert.equal(validateRequest({ op: "open" }), false);
  assert.equal(validateRequest({ op: "ping" }), true);
  assert.equal(validateRequest({ op: "get-location", id: "x" }), true);
  assert.equal(validateRequest({ op: "delete" }), false);
});

test("response: success needs result, failure needs error, and it cannot have both", () => {
  assert.ok(validateResponse({ v: 1, id: "1", ok: true, result: { path: "a.md" } }));
  assert.ok(validateResponse({ v: 1, ok: true, result: null }));
  assert.ok(
    validateResponse({
      v: 1,
      id: "1",
      ok: false,
      error: { code: "outside-project", message: "m" },
    }),
  );
  assert.equal(validateResponse({ v: 1, ok: true }), false);
  assert.equal(validateResponse({ v: 1, ok: false }), false);
  assert.equal(
    validateResponse({ v: 1, ok: false, error: { code: "no-such-code", message: "m" } }),
    false,
  );
  assert.equal(
    validateResponse({ v: 1, ok: true, result: 1, error: { code: "timeout", message: "m" } }),
    false,
  );
});

test("location examples: schema pass/fail matches the expectation", () => {
  for (const item of read("../examples/location.json")) {
    assert.equal(
      validateLocation(item.location),
      item.valid,
      `${item.name}: ${JSON.stringify(validateLocation.errors)}`,
    );
  }
});

test("check examples (location-check): match the schema as a location payload (sha256 replaces auto)", () => {
  const checks = read("../examples/location-check.json");
  assert.ok(checks.length >= 8);
  for (const item of checks) {
    const location = {
      ...item.location,
      file: {
        ...item.location.file,
        sha256: item.location.file.sha256 === "auto" ? "0".repeat(64) : item.location.file.sha256,
      },
    };
    assert.ok(
      validateLocation(location),
      `${item.name}: ${JSON.stringify(validateLocation.errors)}`,
    );
    assert.ok(["ok", "stale", "mismatch"].includes(item.status), item.name);
  }
});

test("get-view also matches the request schema", () => {
  assert.ok(validateRequest({ op: "get-view" }));
});
