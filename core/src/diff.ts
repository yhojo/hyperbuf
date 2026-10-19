// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

/**
 * 2 つのテキストを比べて、最初に違う行(1 始まり)を返す。同じなら null。
 * 末尾に足されただけなら、足された最初の行になる(外部更新への追従: docs/user/configuration.md の followUpdates)。
 */
export function firstChangedLine(before: string, after: string): number | null {
  if (before === after) return null;
  const a = before.split("\n");
  const b = after.split("\n");
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) return i + 1;
  return n + 1;
}
