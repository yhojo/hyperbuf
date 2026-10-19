// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Finds anchors (headings, lines, footnotes) in a rendered document.

/** Prefix that sanitize adds to ids. Must not be removed, to avoid clashes with the app's DOM. */
export const ID_PREFIX = "user-content-";

/** "line:N" points to line N of the source Markdown (the nearest preceding block). */
export function findAnchor(root: HTMLElement, anchor: string): HTMLElement | null {
  const m = /^line:(\d+)$/.exec(anchor);
  if (m) {
    const n = Number(m[1]);
    let best: HTMLElement | null = null;
    for (const el of root.querySelectorAll<HTMLElement>("[data-source-line]")) {
      if (Number(el.dataset["sourceLine"]) <= n) best = el;
      else if (best) break;
    }
    return best ?? root.querySelector<HTMLElement>("[data-source-line]");
  }
  return (
    root.querySelector<HTMLElement>(`#${CSS.escape(ID_PREFIX + anchor)}`) ??
    root.querySelector<HTMLElement>(`#${CSS.escape(anchor)}`)
  );
}

/** Source Markdown line number of the block at the top of the screen (`L40` in the mode line). null if none. */
export function topSourceLine(content: HTMLElement): number | null {
  let line: number | null = null;
  for (const el of content.querySelectorAll<HTMLElement>("[data-source-line]")) {
    if (el.offsetTop > content.scrollTop + 1) break;
    line = Number(el.dataset["sourceLine"]);
  }
  return line ?? (content.querySelector<HTMLElement>("[data-source-line]") ? 1 : null);
}

export interface VisibleAnchor {
  id: string;
  /** How many px the top of the screen is below the top of that element. */
  delta: number;
}

/** The (upper) element with an id closest to the top of the screen. Used to restore the position after an external update. */
export function visibleAnchor(content: HTMLElement): VisibleAnchor | null {
  let best: VisibleAnchor | null = null;
  for (const el of content.querySelectorAll<HTMLElement>("[id]")) {
    if (el.offsetTop <= content.scrollTop + 1) {
      best = { id: el.id, delta: content.scrollTop - el.offsetTop };
    }
  }
  return best;
}

export interface HeadingElement {
  el: HTMLElement;
  level: number;
  /** Position of the top edge within the document (the scrolling element). */
  top: number;
}

/** Heading elements in the document, in order from the start. Used for outline-style navigation. */
export function headingElements(content: HTMLElement): HeadingElement[] {
  return [...content.querySelectorAll<HTMLElement>("h1,h2,h3,h4,h5,h6")].map((el) => ({
    el,
    level: Number(el.tagName.slice(1)),
    top: el.offsetTop,
  }));
}

export interface HeadingInfo {
  level: number;
  text: string;
  /** The anchor without the prefix (used in `path#id` links). */
  id: string;
}

/** Headings are taken from the rendered DOM (ids follow the GitHub scheme, so they may differ from regex-based parsing). */
export function headingsOf(content: HTMLElement): HeadingInfo[] {
  return [...content.querySelectorAll<HTMLElement>("h1,h2,h3,h4,h5,h6")].map((h) => ({
    level: Number(h.tagName.slice(1)),
    text: h.textContent ?? "",
    id: h.id.startsWith(ID_PREFIX) ? h.id.slice(ID_PREFIX.length) : h.id,
  }));
}
