// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

/**
 * Compares two texts and returns the first differing line (1-based), or null if they are the same.
 * If text was only appended, it is the first appended line (following external updates: followUpdates in docs/user/configuration.md).
 */
export function firstChangedLine(before: string, after: string): number | null {
  if (before === after) return null;
  const a = before.split("\n");
  const b = after.split("\n");
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) return i + 1;
  return n + 1;
}
