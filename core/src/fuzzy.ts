// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Fuzzy filtering of file names and the like. Returns candidates containing all whitespace-separated terms, in order of closeness.
// A term is ranked highest as (1) a substring of the file name > (2) a substring of the whole path > (3) a scattered match (character order preserved).

function score(text: string, lower: string, tokens: string[]): number | null {
  const base = lower.slice(lower.lastIndexOf("/") + 1);
  let total = 0;
  for (const t of tokens) {
    let i = base.indexOf(t);
    if (i >= 0) {
      total += 100 + (i === 0 ? 20 : 0) - base.length * 0.1;
      continue;
    }
    i = lower.indexOf(t);
    if (i >= 0) {
      total += 60 - i * 0.05;
      continue;
    }
    let pos = -1;
    let prev = -2;
    let gaps = 0;
    for (const ch of t) {
      pos = lower.indexOf(ch, pos + 1);
      if (pos < 0) return null;
      if (pos !== prev + 1) gaps += 1;
      prev = pos;
    }
    total += 30 - gaps * 3;
  }
  return total - text.length * 0.01;
}

/** Ranges [start, end) of matched characters (for highlighting candidates). Per term, the first place found, in the same priority order as `score`. */
export function matchRanges(candidate: string, query: string): [number, number][] {
  const lower = candidate.toLowerCase();
  const base = lower.lastIndexOf("/") + 1;
  const ranges: [number, number][] = [];
  for (const t of query.toLowerCase().split(/\s+/).filter(Boolean)) {
    let i = lower.indexOf(t, base);
    if (i < 0) i = lower.indexOf(t);
    if (i >= 0) {
      ranges.push([i, i + t.length]);
      continue;
    }
    let pos = -1; // scattered match: one character at a time
    for (const ch of t) {
      pos = lower.indexOf(ch, pos + 1);
      if (pos < 0) break;
      ranges.push([pos, pos + ch.length]);
    }
  }
  return mergeRanges(ranges);
}

/** Merges overlapping or adjacent ranges. */
function mergeRanges(ranges: [number, number][]): [number, number][] {
  const sorted = [...ranges].sort((a, b) => a[0] - b[0]);
  const out: [number, number][] = [];
  for (const [s, e] of sorted) {
    const last = out[out.length - 1];
    if (last && s <= last[1]) last[1] = Math.max(last[1], e);
    else out.push([s, e]);
  }
  return out;
}

export function fuzzyFilter(candidates: readonly string[], query: string, limit = 8): string[] {
  const tokens = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!tokens.length) return candidates.slice(0, limit);
  const top: [number, string][] = [];
  for (const c of candidates) {
    const s = score(c, c.toLowerCase(), tokens);
    if (s === null) continue;
    // Keep only the top `limit` (avoids sorting even with thousands of candidates)
    const worst = top[top.length - 1];
    if (top.length < limit || (worst && s > worst[0])) {
      top.push([s, c]);
      top.sort((a, b) => b[0] - a[0]);
      if (top.length > limit) top.pop();
    }
  }
  return top.map(([, c]) => c);
}
