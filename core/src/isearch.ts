// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// The search part of incremental search in a document (C-s / C-r). A pure function with no DOM dependency.

/** Case-sensitive only when the query contains an uppercase letter (Emacs's default behavior). */
export function isCaseSensitive(query: string): boolean {
  return query !== query.toLowerCase();
}

/** Start positions of all matches (non-overlapping; the next search continues from the end of a match). */
export function findAll(text: string, query: string, caseSensitive: boolean): number[] {
  if (!query) return [];
  const haystack = caseSensitive ? text : text.toLowerCase();
  const needle = caseSensitive ? query : query.toLowerCase();
  const found: number[] = [];
  let from = 0;
  for (;;) {
    const i = haystack.indexOf(needle, from);
    if (i < 0) return found;
    found.push(i);
    from = i + Math.max(needle.length, 1);
  }
}

export interface Step {
  /** Index in `matches` of the match to select. null if there are no matches. */
  index: number | null;
  /** Whether the search reached an end and wrapped to the opposite end (Emacs's "Wrapped"). */
  wrapped: boolean;
}

/**
 * The next (direction = 1) or previous (-1) match. `current` is the index of the currently selected match (null if none).
 * On reaching an end, wraps to the opposite end.
 */
export function step(count: number, current: number | null, direction: 1 | -1): Step {
  if (count === 0) return { index: null, wrapped: false };
  if (current === null) return { index: direction === 1 ? 0 : count - 1, wrapped: false };
  const next = current + direction;
  if (next >= count) return { index: 0, wrapped: true };
  if (next < 0) return { index: count - 1, wrapped: true };
  return { index: next, wrapped: false };
}

/**
 * The match to select first when the input changes (or when the search starts): the first match at or after the base position (`from`).
 * If none, wraps to the opposite end (wrapped). If the direction is backward, the last match at or before `from`.
 */
export function firstMatch(matches: readonly number[], from: number, direction: 1 | -1): Step {
  if (matches.length === 0) return { index: null, wrapped: false };
  if (direction === 1) {
    const i = matches.findIndex((m) => m >= from);
    return i < 0 ? { index: 0, wrapped: true } : { index: i, wrapped: false };
  }
  for (let i = matches.length - 1; i >= 0; i--) {
    if ((matches[i] ?? Infinity) <= from) return { index: i, wrapped: false };
  }
  return { index: matches.length - 1, wrapped: true };
}
