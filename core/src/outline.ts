// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Decisions for outline-mode-style heading navigation (docs/dev/interaction-model.md). Pure functions with no DOM dependency.
// "The current position" is the top edge of the screen (scrollTop). Headings are in order from the start of the document (tops holds each heading's top).
//
//   C-c C-n  next heading            C-c C-p  previous heading
//   C-c C-f  next at the same level  C-c C-b  previous at the same level   C-c C-u  up to the parent-level heading
//
// When the top of the screen is at (almost) the top of a heading, we consider "being at that heading" (the EPS range).

/** Tolerance (px) within which a heading's top counts as equal to the top of the screen. */
export const EPS = 8;

/** The heading whose section we are in (the last heading whose top is at or above the top of the screen). -1 if none. */
export function currentIndex(tops: readonly number[], scrollTop: number): number {
  let current = -1;
  for (let i = 0; i < tops.length; i++) {
    if ((tops[i] ?? Infinity) <= scrollTop + EPS) current = i;
    else break;
  }
  return current;
}

/** Next heading: the first heading whose top is below the top of the screen. */
export function nextIndex(tops: readonly number[], scrollTop: number): number | null {
  const i = tops.findIndex((t) => t > scrollTop + EPS);
  return i < 0 ? null : i;
}

/** Previous heading: the last heading whose top is above the top of the screen. */
export function previousIndex(tops: readonly number[], scrollTop: number): number | null {
  for (let i = tops.length - 1; i >= 0; i--) {
    if ((tops[i] ?? Infinity) < scrollTop - EPS) return i;
  }
  return null;
}

/** Parent-level heading: the nearest heading before the current section's heading with a smaller level. */
export function upIndex(levels: readonly number[], current: number): number | null {
  const level = levels[current];
  if (level === undefined) return null;
  for (let i = current - 1; i >= 0; i--) {
    if ((levels[i] ?? Infinity) < level) return i;
  }
  return null;
}

/** Next heading at the same level. Does not cross a parent-level heading (siblings under the same parent only). */
export function sameLevelForward(levels: readonly number[], current: number): number | null {
  const level = levels[current];
  if (level === undefined) return null;
  for (let i = current + 1; i < levels.length; i++) {
    const l = levels[i] ?? Infinity;
    if (l < level) return null;
    if (l === level) return i;
  }
  return null;
}

/** Previous heading at the same level. Does not cross a parent-level heading. */
export function sameLevelBackward(levels: readonly number[], current: number): number | null {
  const level = levels[current];
  if (level === undefined) return null;
  for (let i = current - 1; i >= 0; i--) {
    const l = levels[i] ?? Infinity;
    if (l < level) return null;
    if (l === level) return i;
  }
  return null;
}
