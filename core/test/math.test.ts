// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { unescapeMathUnderscores as u } from "../src/math.ts";

test("数式の中の \\_ は、下付き文字の _ に戻す", () => {
  assert.equal(u("f\\_{2}"), "f_{2}");
  assert.equal(u("f\\_{2} = 2^{BW} f_{1}"), "f_{2} = 2^{BW} f_{1}");
  assert.equal(u("\\frac{f\\_{2}}{f\\_{1}}"), "\\frac{f_{2}}{f_{1}}");
  assert.equal(u("a\\_1 + b\\_2"), "a_1 + b_2");
});

test("\\_ がなければ、そのまま", () => {
  const tex = "\\left[ \\frac{\\log{x}}{\\log{2}} \\right] + x_{1}";
  assert.equal(u(tex), tex);
});

test("\\text{…} や \\mathrm{…} の中の \\_ は、文字としての下線なので、残す", () => {
  assert.equal(u("\\text{snake\\_case}"), "\\text{snake\\_case}");
  assert.equal(u("\\mathrm{max\\_value}"), "\\mathrm{max\\_value}");
  assert.equal(u("\\operatorname{arg\\_max}_{x}"), "\\operatorname{arg\\_max}_{x}");
  // Text outside the argument is returned unchanged (including nested braces)
  assert.equal(u("\\text{a {b\\_c} d} + f\\_2"), "\\text{a {b\\_c} d} + f_2");
  assert.equal(u("\\text{x}\\_1"), "\\text{x}_1");
});

test("\\\\ のあとの _ や、\\\\_ は、そのまま", () => {
  assert.equal(u("a \\\\ \\_b"), "a \\\\ _b");
  assert.equal(u("a \\\\_b \\_c"), "a \\\\_b _c");
});

test("引数のないコマンドや、末尾のバックスラッシュで壊れない", () => {
  assert.equal(u("\\alpha\\_1"), "\\alpha_1");
  assert.equal(u("x\\"), "x\\");
  assert.equal(u("\\mathrm x\\_1"), "\\mathrm x_1");
  assert.equal(u("\\mathrm{a}\\_b"), "\\mathrm{a}_b");
});
