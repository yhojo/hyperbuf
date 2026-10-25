// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Operation model (docs/dev/interaction-model.md). Pure logic with no DOM or shell dependency.

import { parseVirtualPath } from "./names.ts";
import { dirname, joinPath } from "./paths.ts";

export interface Buffer {
  readonly path: string;
  text: string;
  /** Increases every time the content is updated. Used to decide whether to re-render. */
  version: number;
  /** The file was deleted (or moved). The buffer is kept and the header says so. */
  missing?: boolean;
}

export interface HistoryEntry {
  path: string;
  anchor: string | null;
  scroll: number;
  /** Index of the link selected with TAB / S-TAB (in memory only; not saved in the session). */
  link?: number;
}

export interface Win {
  readonly id: number;
  history: HistoryEntry[];
  index: number;
}

export type SplitDirection = "row" | "col";

export type LayoutNode =
  | { type: "leaf"; win: Win }
  | {
      type: "split";
      dir: SplitDirection;
      children: [LayoutNode, LayoutNode];
      /** Fraction occupied by the first child (default 0.5 if omitted). */
      ratio?: number;
    };

export interface Model {
  buffers: Map<string, Buffer>;
  /** Buffer paths in most-recently-used order. Managed separately from the reference history. */
  mru: string[];
  winSeq: number;
  root: LayoutNode;
  selected: number;
}

export interface LinkTarget {
  path: string;
  anchor: string | null;
}

/**
 * Resolves an href relative to the current document (absolute path) into an absolute path. null for external URLs.
 * An href starting with `/` is treated as an absolute file system path (there is no unit called a project).
 */
export function resolveLink(fromPath: string, href: string): LinkTarget | null {
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) return null;
  const hash = href.indexOf("#");
  const pathPart = hash < 0 ? href : href.slice(0, hash);
  const anchor = hash < 0 ? null : href.slice(hash + 1);
  if (pathPart === "") return { path: fromPath, anchor };
  // Link URLs are percent-encoded (Japanese file names, etc.), so decode them
  let decoded = pathPart;
  try {
    decoded = decodeURIComponent(pathPart);
  } catch {
    // Use an invalid encoding as is
  }
  // A relative link from a virtual buffer (search results, etc.) is based on the origin directory (`/` if none)
  const base = isVirtualPath(fromPath)
    ? (parseVirtualPath(fromPath).dir ?? "/")
    : dirname(fromPath);
  return { path: joinPath(base, decoded), anchor };
}

/** Whether this is the path of a buffer that does not correspond to a file (such as `*search: …*`). A real `.md` path does not end with `*`. */
export function isVirtualPath(path: string): boolean {
  return path.length >= 2 && path.startsWith("*") && path.endsWith("*");
}

export function createModel(): Model {
  const win: Win = { id: 1, history: [], index: -1 };
  return { buffers: new Map(), mru: [], winSeq: 1, root: leaf(win), selected: win.id };
}

function makeWindow(model: Model, from: Win): Win {
  return {
    id: ++model.winSeq,
    history: from.history.map((e) => ({ ...e })),
    index: from.index,
  };
}

const leaf = (win: Win): LayoutNode => ({ type: "leaf", win });

export function windows(model: Model): Win[] {
  const out: Win[] = [];
  const walk = (node: LayoutNode): void => {
    if (node.type === "leaf") out.push(node.win);
    else node.children.forEach(walk);
  };
  walk(model.root);
  return out;
}

export function selectedWindow(model: Model): Win {
  const win = windows(model).find((w) => w.id === model.selected);
  if (!win) throw new Error("No selected window");
  return win;
}

export function currentEntry(win: Win): HistoryEntry | null {
  return win.history[win.index] ?? null;
}

export function openBuffer(model: Model, path: string, text: string): Buffer {
  const existing = model.buffers.get(path);
  const buf: Buffer = existing ?? { path, text: "", version: 0 };
  buf.text = text;
  buf.version += 1;
  model.buffers.set(path, buf);
  return buf;
}

function touch(model: Model, path: string): void {
  model.mru = [path, ...model.mru.filter((p) => p !== path)];
}

/** Buffer switches (C-x b), links and heading jumps are all pushed onto the history. */
export function visit(model: Model, win: Win, path: string, anchor: string | null = null): void {
  const cur = currentEntry(win);
  if (cur && cur.path === path && cur.anchor === anchor) return;
  win.history.splice(win.index + 1);
  win.history.push({ path, anchor, scroll: 0 });
  win.index = win.history.length - 1;
  touch(model, path);
}

/**
 * Opens from outside (editor integration) with a position. If it is the same as the displayed document, replaces only the position without pushing history
 * (like `goto-line` in Emacs; history does not pile up with every open).
 */
export function jump(model: Model, win: Win, path: string, anchor: string | null = null): void {
  const cur = currentEntry(win);
  if (cur && cur.path === path) {
    if (anchor !== null) win.history[win.index] = { path, anchor, scroll: 0 };
    touch(model, path);
    return;
  }
  visit(model, win, path, anchor);
}

export function back(model: Model, win: Win): boolean {
  if (win.index <= 0) return false;
  win.index -= 1;
  const entry = currentEntry(win);
  if (entry) touch(model, entry.path);
  return true;
}

export function forward(model: Model, win: Win): boolean {
  if (win.index >= win.history.length - 1) return false;
  win.index += 1;
  const entry = currentEntry(win);
  if (entry) touch(model, entry.path);
  return true;
}

/** Moves to the start of the history (`C-a`). false if already at the start. */
export function backToStart(model: Model, win: Win): boolean {
  if (win.index <= 0) return false;
  win.index = 0;
  const entry = currentEntry(win);
  if (entry) touch(model, entry.path);
  return true;
}

/** Moves to the end of the history (`C-e`). false if already at the end. */
export function forwardToEnd(model: Model, win: Win): boolean {
  const last = win.history.length - 1;
  if (win.index >= last) return false;
  win.index = last;
  const entry = currentEntry(win);
  if (entry) touch(model, entry.path);
  return true;
}

function findParent(
  node: LayoutNode,
  target: LayoutNode,
  parent: LayoutNode | null = null,
): LayoutNode | null {
  if (node === target) return parent;
  if (node.type === "split") {
    for (const child of node.children) {
      const found = findParent(child, target, node);
      if (found) return found;
    }
  }
  return null;
}

function nodeOf(model: Model, win: Win): LayoutNode {
  let found: LayoutNode | null = null;
  const walk = (node: LayoutNode): void => {
    if (node.type === "leaf") {
      if (node.win === win) found = node;
    } else node.children.forEach(walk);
  };
  walk(model.root);
  if (!found) throw new Error("Window not in layout");
  return found;
}

function firstLeaf(node: LayoutNode): Extract<LayoutNode, { type: "leaf" }> {
  return node.type === "leaf" ? node : firstLeaf(node.children[0]);
}

function replaceChild(parent: LayoutNode, old: LayoutNode, next: LayoutNode): void {
  if (parent.type !== "split") throw new Error("Not a split");
  parent.children[parent.children[0] === old ? 0 : 1] = next;
}

/**
 * dir: "col" (stack vertically = C-x 2) / "row" (side by side = C-x 3).
 * The new window gets a copy of the history of the window it was split from. The selection stays with the original.
 */
export function split(model: Model, dir: SplitDirection): Win {
  const win = selectedWindow(model);
  const node = nodeOf(model, win);
  const fresh = makeWindow(model, win);
  const replacement: LayoutNode = { type: "split", dir, children: [leaf(win), leaf(fresh)] };
  const parent = findParent(model.root, node);
  if (!parent) model.root = replacement;
  else replaceChild(parent, node, replacement);
  return fresh;
}

export const MIN_RATIO = 0.1;
export const MAX_RATIO = 0.9;

/** The innermost split in direction `dir` that contains `win` (also returns whether `win` is on the first child's side). */
export function resizableSplit(
  model: Model,
  win: Win,
  dir: SplitDirection,
): { node: Extract<LayoutNode, { type: "split" }>; first: boolean } | null {
  let child: LayoutNode | null = nodeOf(model, win);
  while (child) {
    const parent: LayoutNode | null = findParent(model.root, child);
    if (parent?.type === "split" && parent.dir === dir) {
      return { node: parent, first: parent.children[0] === child };
    }
    child = parent;
  }
  return null;
}

/**
 * Grows `win` in direction `dir` by `delta` of the whole split (shrinks if negative).
 * The neighbor shrinks by that amount. false if there is no split in the growing direction.
 */
export function resizeWindow(model: Model, win: Win, dir: SplitDirection, delta: number): boolean {
  const found = resizableSplit(model, win, dir);
  if (!found) return false;
  const current = found.node.ratio ?? 0.5;
  found.node.ratio = clampRatio(found.first ? current + delta : current - delta);
  return true;
}

/**
 * The split that has the boundary at the bottom (`col`) or right (`row`) edge of `win`. null if `win` is at the edge of the screen.
 * Searching from the inner splits, finds the first one where the side containing `win` is "top (left)" (the boundary moved by dragging the mode line).
 */
function boundaryAfter(
  model: Model,
  win: Win,
  dir: SplitDirection,
): Extract<LayoutNode, { type: "split" }> | null {
  let child: LayoutNode | null = nodeOf(model, win);
  while (child) {
    const parent: LayoutNode | null = findParent(model.root, child);
    if (parent?.type === "split" && parent.dir === dir && parent.children[0] === child) {
      return parent;
    }
    child = parent;
  }
  return null;
}

/** The boundary below the mode line (vertical split). */
export const boundaryBelow = (model: Model, win: Win) => boundaryAfter(model, win, "col");

/** The boundary at the right of a window (horizontal split). Moved by dragging the right end of the mode line. */
export const boundaryRight = (model: Model, win: Win) => boundaryAfter(model, win, "row");

export function clampRatio(r: number): number {
  return Math.min(MAX_RATIO, Math.max(MIN_RATIO, r));
}

export function deleteWindow(model: Model): boolean {
  return removeWindow(model, selectedWindow(model));
}

/** Removes a window and collapses the split. The only window cannot be removed (false). If it was selected, selection moves to the neighbor. */
export function removeWindow(model: Model, win: Win): boolean {
  const node = nodeOf(model, win);
  const parent = findParent(model.root, node);
  if (!parent || parent.type !== "split") return false;
  const sibling = parent.children[0] === node ? parent.children[1] : parent.children[0];
  const grand = findParent(model.root, parent);
  if (!grand) model.root = sibling;
  else replaceChild(grand, parent, sibling);
  if (model.selected === win.id) model.selected = firstLeaf(sibling).win.id;
  return true;
}

export function deleteOthers(model: Model): void {
  model.root = leaf(selectedWindow(model));
}

/**
 * Closes a buffer. Removes references to that buffer from every window's history
 * (so it never creates a state where a closed buffer can be shown by Back / Forward).
 * A window that was showing the closed buffer shows the previous reference in its history.
 * @returns windows whose history became empty (nothing to show, so the caller opens another buffer).
 */
export function killBuffer(model: Model, path: string): Win[] {
  model.buffers.delete(path);
  model.mru = model.mru.filter((p) => p !== path);
  const empty: Win[] = [];
  for (const win of windows(model)) {
    // Compute the new index from the number of references remaining before the current position (index)
    let kept = 0;
    let newIndex = -1;
    const history: HistoryEntry[] = [];
    win.history.forEach((entry, i) => {
      if (entry.path === path) return;
      history.push(entry);
      if (i <= win.index) newIndex = kept;
      kept += 1;
    });
    win.history = history;
    win.index = history.length === 0 ? -1 : Math.max(newIndex, 0);
    if (history.length === 0) empty.push(win);
  }
  return empty;
}

export function otherWindow(model: Model): void {
  const all = windows(model);
  const i = all.findIndex((w) => w.id === model.selected);
  const next = all[(i + 1) % all.length];
  if (next) model.selected = next.id;
}
