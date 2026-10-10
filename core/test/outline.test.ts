// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import {
  currentIndex,
  EPS,
  nextIndex,
  previousIndex,
  sameLevelBackward,
  sameLevelForward,
  upIndex,
} from "../src/outline.ts";

// 見出しの構成の例:
//   0: # A            (level 1, top 0)
//   1: ## A1          (level 2, top 100)
//   2: ### A1a        (level 3, top 200)
//   3: ## A2          (level 2, top 300)
//   4: # B            (level 1, top 400)
//   5: ## B1          (level 2, top 500)
const levels = [1, 2, 3, 2, 1, 2];
const tops = [0, 100, 200, 300, 400, 500];

test("いまの節: 画面の上端以前の、最後の見出し", () => {
  assert.equal(currentIndex(tops, 0), 0);
  assert.equal(currentIndex(tops, 150), 1);
  assert.equal(currentIndex(tops, 100 - EPS), 1); // 見出しの上端に(ほぼ)いる
  assert.equal(currentIndex(tops, 100 - EPS - 1), 0);
  assert.equal(currentIndex(tops, 9999), 5);
  assert.equal(currentIndex([50], 0), -1); // 最初の見出しの前
  assert.equal(currentIndex([], 0), -1);
});

test("次の見出し: 画面の上端より下の、最初の見出し", () => {
  assert.equal(nextIndex(tops, 0), 1);
  assert.equal(nextIndex(tops, 150), 2);
  assert.equal(nextIndex(tops, 100), 2); // 見出しの上端にいるとき、次は、その次
  assert.equal(nextIndex(tops, 500), null);
  assert.equal(nextIndex(tops, -100), 0);
  assert.equal(nextIndex([], 0), null);
});

test("前の見出し: 画面の上端より上の、最後の見出し", () => {
  assert.equal(previousIndex(tops, 150), 1); // 節の途中では、その節の見出しへ
  assert.equal(previousIndex(tops, 100), 0); // 見出しの上端にいるとき、前は、その前
  assert.equal(previousIndex(tops, 0), null);
  assert.equal(previousIndex(tops, 9999), 5);
  assert.equal(previousIndex([], 0), null);
});

test("上のレベルの見出し", () => {
  assert.equal(upIndex(levels, 2), 1); // A1a → A1
  assert.equal(upIndex(levels, 1), 0); // A1 → A
  assert.equal(upIndex(levels, 3), 0); // A2 → A
  assert.equal(upIndex(levels, 5), 4); // B1 → B
  assert.equal(upIndex(levels, 0), null);
  assert.equal(upIndex(levels, 4), null);
  assert.equal(upIndex(levels, -1), null);
});

test("同じレベルの、次・前(親をまたがない)", () => {
  assert.equal(sameLevelForward(levels, 1), 3); // A1 → A2
  assert.equal(sameLevelForward(levels, 3), null); // A2 → なし(次は、親の兄弟 B)
  assert.equal(sameLevelForward(levels, 0), 4); // A → B
  assert.equal(sameLevelForward(levels, 2), null); // A1a: 兄弟なし
  assert.equal(sameLevelBackward(levels, 3), 1); // A2 → A1
  assert.equal(sameLevelBackward(levels, 1), null); // A1 → なし
  assert.equal(sameLevelBackward(levels, 4), 0); // B → A
  assert.equal(sameLevelBackward(levels, 5), null); // B1: 前の兄弟なし
});

test("見出しのレベルが飛んでいても動く(# → ###)", () => {
  const skip = [1, 3, 3, 1];
  assert.equal(upIndex(skip, 1), 0);
  assert.equal(sameLevelForward(skip, 1), 2);
  assert.equal(sameLevelForward(skip, 2), null);
});
