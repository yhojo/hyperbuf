// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Saving and restoring the session (pure logic with no DOM or shell dependency).
// What is saved: the split layout, each window's reference history (documents, anchors, reading positions), the selected window,
// and the buffer most-recently-used order. Document contents are not saved (they are re-read from the host on restore).
// Saved data is treated as untrusted input and strictly validated (if it is broken, it is not used).

import { currentEntry, isVirtualPath, MAX_RATIO, MIN_RATIO, windows } from "./model.ts";
import type { HistoryEntry, LayoutNode, Model, Win } from "./model.ts";

export const SESSION_VERSION = 1;

// Limits. Keep the same values as the table in docs/dev/session-restore.md §4 (when you change a value, fix the table too.
// core/test/session-docs.test.ts checks that they match).
/** Maximum number of history entries saved for one window (keeps entries around the current position). */
export const MAX_HISTORY = 100;
export const MAX_MRU = 200;
export const MAX_WINDOWS = 32;
export const MAX_DEPTH = 16;
export const MAX_STRING = 4096;
/** Maximum number of characters of a saved selection (longer ones are not saved). */
export const MAX_SELECTION = 4096;

export type SessionNode =
  | { type: "leaf"; id: number; index: number; history: HistoryEntry[] }
  | {
      type: "split";
      dir: "row" | "col";
      children: [SessionNode, SessionNode];
      ratio?: number;
    };

/**
 * A selection (text selected in the document). Expressed as a position in the displayed text (the rendered string),
 * and on restore it is used only if the string at that position matches `text` (not used if the document has been rewritten).
 */
export interface SessionSelection {
  /** The window that had the selection. */
  win: number;
  /** The window's current document at that time. */
  path: string;
  start: number;
  end: number;
  text: string;
}

export interface SessionSnapshot {
  version: typeof SESSION_VERSION;
  selected: number;
  winSeq: number;
  mru: string[];
  root: SessionNode;
  selection?: SessionSelection;
}

/** Only real documents are saved (virtual buffers such as `*search: …*` cannot be restored). */
const persistable = (entry: HistoryEntry): boolean => !isVirtualPath(entry.path);

function snapshotWindow(win: Win): SessionNode | null {
  const kept: HistoryEntry[] = [];
  let index = -1;
  win.history.forEach((entry, i) => {
    if (!persistable(entry)) return;
    if (i <= win.index) index = kept.length;
    kept.push({ path: entry.path, anchor: entry.anchor, scroll: entry.scroll });
  });
  if (kept.length === 0) return null;
  // Too much history is trimmed to the newest MAX_HISTORY entries, including the current position
  const from = Math.max(
    0,
    Math.min(Math.max(index, 0) - Math.floor(MAX_HISTORY / 2), kept.length - MAX_HISTORY),
  );
  const history = kept.slice(from, from + MAX_HISTORY);
  return { type: "leaf", id: win.id, index: Math.max(index, 0) - from, history };
}

function snapshotNode(node: LayoutNode): SessionNode | null {
  if (node.type === "leaf") return snapshotWindow(node.win);
  const [a, b] = node.children.map(snapshotNode);
  if (a && b) {
    const out: SessionNode = { type: "split", dir: node.dir, children: [a, b] };
    if (node.ratio !== undefined) out.ratio = node.ratio;
    return out;
  }
  return a ?? b ?? null; // if one side has nothing to save, collapse the split
}

/** A copy of the current state for saving. null if there is nothing to save. */
export function takeSnapshot(
  model: Model,
  selection: SessionSelection | null = null,
): SessionSnapshot | null {
  const root = snapshotNode(model.root);
  if (!root) return null;
  const ids = leafIds(root);
  const snapshot: SessionSnapshot = {
    version: SESSION_VERSION,
    selected: ids.includes(model.selected) ? model.selected : (ids[0] ?? 1),
    winSeq: model.winSeq,
    mru: model.mru.filter((p) => !isVirtualPath(p)).slice(0, MAX_MRU),
    root,
  };
  if (selection && ids.includes(selection.win) && !isVirtualPath(selection.path)) {
    snapshot.selection = selection;
  }
  return snapshot;
}

function leafIds(node: SessionNode): number[] {
  return node.type === "leaf" ? [node.id] : node.children.flatMap(leafIds);
}

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const isPath = (v: unknown): v is string =>
  typeof v === "string" && v.length > 0 && v.length <= MAX_STRING && !v.includes("\0");

function parseEntry(v: unknown): HistoryEntry | null {
  if (!isRecord(v) || !isPath(v["path"])) return null;
  const anchor = v["anchor"];
  const scroll = v["scroll"];
  if (anchor !== null && !(typeof anchor === "string" && anchor.length <= MAX_STRING)) return null;
  if (typeof scroll !== "number" || !Number.isFinite(scroll) || scroll < 0) return null;
  return { path: v["path"], anchor, scroll };
}

function parseNode(v: unknown, depth: number, budget: { windows: number }): SessionNode | null {
  if (!isRecord(v) || depth > MAX_DEPTH) return null;
  if (v["type"] === "leaf") {
    const { id, index, history } = v;
    if (typeof id !== "number" || !Number.isInteger(id) || id < 1) return null;
    if (typeof index !== "number" || !Number.isInteger(index)) return null;
    if (!Array.isArray(history) || history.length > MAX_HISTORY) return null;
    if (--budget.windows < 0) return null;
    const entries = history.map(parseEntry);
    if (entries.some((e) => e === null)) return null;
    return { type: "leaf", id, index, history: entries as HistoryEntry[] };
  }
  if (v["type"] === "split") {
    const { dir, children } = v;
    if (dir !== "row" && dir !== "col") return null;
    if (!Array.isArray(children) || children.length !== 2) return null;
    const a = parseNode(children[0], depth + 1, budget);
    const b = parseNode(children[1], depth + 1, budget);
    if (!a || !b) return null;
    const ratio = v["ratio"];
    const valid = typeof ratio === "number" && ratio >= MIN_RATIO && ratio <= MAX_RATIO;
    return valid
      ? { type: "split", dir, children: [a, b], ratio }
      : { type: "split", dir, children: [a, b] };
  }
  return null;
}

/** Validation of saved data. null if the shape is wrong (it is not used partially). */
export function parseSnapshot(value: unknown): SessionSnapshot | null {
  if (!isRecord(value) || value["version"] !== SESSION_VERSION) return null;
  const { selected, winSeq, mru, root } = value;
  if (typeof selected !== "number" || typeof winSeq !== "number") return null;
  if (!Number.isInteger(winSeq) || winSeq < 1) return null;
  if (!Array.isArray(mru) || mru.length > MAX_MRU || !mru.every(isPath)) return null;
  const node = parseNode(root, 0, { windows: MAX_WINDOWS });
  if (!node) return null;
  const ids = leafIds(node);
  if (new Set(ids).size !== ids.length) return null;
  const snapshot: SessionSnapshot = { version: SESSION_VERSION, selected, winSeq, mru, root: node };
  // If only the selection is broken, discard only the selection (the rest of the restore is usable)
  const selection = parseSelection(value["selection"]);
  if (selection && ids.includes(selection.win)) snapshot.selection = selection;
  return snapshot;
}

function parseSelection(v: unknown): SessionSelection | null {
  if (!isRecord(v) || !isPath(v["path"])) return null;
  const { win, start, end, text } = v;
  if (typeof win !== "number" || !Number.isInteger(win) || win < 1) return null;
  if (typeof start !== "number" || typeof end !== "number") return null;
  if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || end <= start) return null;
  if (typeof text !== "string" || text.length !== end - start || text.length > MAX_SELECTION) {
    return null;
  }
  return { win, path: v["path"], start, end, text };
}

/**
 * The selection usable for the restored model. null unless the window shows the same document as when it was saved
 * (for example, a vanished document was dropped and the current position changed).
 */
export function restoredSelection(
  snapshot: SessionSnapshot,
  model: Model,
): SessionSelection | null {
  const sel = snapshot.selection;
  if (!sel) return null;
  const win = windows(model).find((w) => w.id === sel.win);
  const entry = win ? currentEntry(win) : null;
  return entry && entry.path === sel.path ? sel : null;
}

/** A set of paths of existing documents, or a predicate for whether one exists. */
type Available = ReadonlySet<string> | ((path: string) => boolean);

const hasIn = (available: Available): ((path: string) => boolean) =>
  typeof available === "function" ? available : (p) => available.has(p);

function restoreWindow(node: Extract<SessionNode, { type: "leaf" }>, available: Available) {
  const history: HistoryEntry[] = [];
  let index = -1;
  node.history.forEach((entry, i) => {
    if (!hasIn(available)(entry.path)) return; // drop vanished documents from the history
    if (i <= node.index) index = history.length;
    history.push({ ...entry });
  });
  if (history.length === 0) return null;
  const win: Win = { id: node.id, history, index: Math.max(index, 0) };
  return win;
}

function restoreNode(node: SessionNode, available: Available): LayoutNode | null {
  if (node.type === "leaf") {
    const win = restoreWindow(node, available);
    return win ? { type: "leaf", win } : null;
  }
  const [a, b] = node.children.map((c) => restoreNode(c, available));
  if (a && b) {
    const out: LayoutNode = { type: "split", dir: node.dir, children: [a, b] };
    if (node.ratio !== undefined) out.ratio = node.ratio;
    return out;
  }
  return a ?? b ?? null;
}

/**
 * Builds a model from the saved state (buffer contents are empty; the caller reads them from the host).
 * `available`: paths of documents that exist now (a set, or a predicate). Vanished documents are dropped from the history and the MRU order.
 * null if no window can be restored.
 */
export function restoreModel(snapshot: SessionSnapshot, available: Available): Model | null {
  const root = restoreNode(snapshot.root, available);
  if (!root) return null;
  const ids: number[] = [];
  const walk = (n: LayoutNode): void => {
    if (n.type === "leaf") ids.push(n.win.id);
    else n.children.forEach(walk);
  };
  walk(root);
  return {
    buffers: new Map(),
    mru: snapshot.mru.filter(hasIn(available)),
    winSeq: Math.max(snapshot.winSeq, ...ids),
    root,
    selected: ids.includes(snapshot.selected) ? snapshot.selected : (ids[0] ?? 1),
  };
}

/** Paths of the documents (everything in the history) that the restored model uses for display. */
export function referencedPaths(model: Model): string[] {
  const out = new Set<string>();
  const walk = (n: LayoutNode): void => {
    if (n.type === "leaf") n.win.history.forEach((e) => out.add(e.path));
    else n.children.forEach(walk);
  };
  walk(model.root);
  return [...out];
}
