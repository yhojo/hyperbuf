// JSON Schema が、共有の例(examples/)と食い違っていないかを確かめる。
// 同じ例を、Swift のサーバー・CLI・Emacs も使う(各自の適合テスト)。
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

test("open の検証例: スキーマの合否が、期待(ok かエラー)と一致する", () => {
  for (const item of read("../examples/open-validation.json")) {
    const valid = validateRequest(item.request);
    assert.equal(
      valid,
      item.expect === "ok",
      `${item.name}: ${JSON.stringify(validateRequest.errors)}`,
    );
  }
});

test("URL の例から作る要求は、スキーマに合う", () => {
  for (const item of read("../examples/url.json")) {
    if (!item.request) continue;
    assert.ok(
      validateRequest(item.request),
      `${item.name}: ${JSON.stringify(validateRequest.errors)}`,
    );
  }
});

test("open には path が必須、ping には不要", () => {
  assert.equal(validateRequest({ op: "open" }), false);
  assert.equal(validateRequest({ op: "ping" }), true);
  assert.equal(validateRequest({ op: "get-location", id: "x" }), true);
  assert.equal(validateRequest({ op: "delete" }), false);
});

test("応答: 成功には result、失敗には error が要り、両方は持てない", () => {
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

test("位置(location)の例: スキーマの合否が、期待と一致する", () => {
  for (const item of read("../examples/location.json")) {
    assert.equal(
      validateLocation(item.location),
      item.valid,
      `${item.name}: ${JSON.stringify(validateLocation.errors)}`,
    );
  }
});

test("照合の例(location-check): 位置のペイロードとして、スキーマに合う(sha256 は auto を置き換える)", () => {
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

test("get-view も、リクエストのスキーマに合う", () => {
  assert.ok(validateRequest({ op: "get-view" }));
});
