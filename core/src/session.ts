// セッションの保存と復元(DOM やシェルに依存しない純粋なロジック)。
// 保存するのは、分割の配置、window ごとの参照履歴(文書・アンカー・閲覧位置)、選択中の window、
// buffer の最近使った順。文書の内容は保存しない(復元時に、ホストから読み直す)。
// 保存されたデータは、信頼しない入力として、厳密に検証する(壊れていたら、使わない)。

import { currentEntry, isVirtualPath, windows } from "./model.ts";
import type { HistoryEntry, LayoutNode, Model, Win } from "./model.ts";

export const SESSION_VERSION = 1;

/** 1 つの window の履歴の、保存する最大の件数(現在位置の前後を残す)。 */
export const MAX_HISTORY = 100;
const MAX_MRU = 200;
const MAX_WINDOWS = 32;
const MAX_DEPTH = 16;
const MAX_STRING = 4096;
/** 保存する選択範囲の、最大の文字数(長いものは、保存しない)。 */
export const MAX_SELECTION = 4096;

export type SessionNode =
  | { type: "leaf"; id: number; index: number; history: HistoryEntry[] }
  | { type: "split"; dir: "row" | "col"; children: [SessionNode, SessionNode] };

/**
 * 選択範囲(文書内で選択していたテキスト)。表示されたテキスト(描画後の文字列)の中の位置で表し、
 * 復元のときは、その位置の文字列が `text` と一致するときだけ使う(文書が書き換わっていれば、使わない)。
 */
export interface SessionSelection {
  /** 選択があった window。 */
  win: number;
  /** そのときの、window の現在の文書。 */
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

/** 実在の文書だけを、保存の対象にする(`*search: …*` などの仮想 buffer は、復元できない)。 */
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
  // 多すぎる履歴は、現在位置を含む、新しい側の MAX_HISTORY 件にする
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
  if (a && b) return { type: "split", dir: node.dir, children: [a, b] };
  return a ?? b ?? null; // 片方に保存できるものがなければ、分割をたたむ
}

/** いまの状態の、保存用の写し。保存できるものがなければ null。 */
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
    return a && b ? { type: "split", dir, children: [a, b] } : null;
  }
  return null;
}

/** 保存されたデータの検証。形が正しくなければ null(部分的には、使わない)。 */
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
  // 選択範囲だけが壊れているときは、選択範囲だけを捨てる(ほかの復元は、使える)
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
 * 復元した model に対して、使える選択範囲。その window が、保存したときと同じ文書を表示していなければ
 * (なくなった文書が外れて、現在位置が変わったなど)、null。
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

function restoreWindow(
  node: Extract<SessionNode, { type: "leaf" }>,
  available: ReadonlySet<string>,
) {
  const history: HistoryEntry[] = [];
  let index = -1;
  node.history.forEach((entry, i) => {
    if (!available.has(entry.path)) return; // なくなった文書は、履歴から外す
    if (i <= node.index) index = history.length;
    history.push({ ...entry });
  });
  if (history.length === 0) return null;
  const win: Win = { id: node.id, history, index: Math.max(index, 0) };
  return win;
}

function restoreNode(node: SessionNode, available: ReadonlySet<string>): LayoutNode | null {
  if (node.type === "leaf") {
    const win = restoreWindow(node, available);
    return win ? { type: "leaf", win } : null;
  }
  const [a, b] = node.children.map((c) => restoreNode(c, available));
  if (a && b) return { type: "split", dir: node.dir, children: [a, b] };
  return a ?? b ?? null;
}

/**
 * 保存された状態から、model を作る(buffer の内容は空。呼び出し側が、ホストから読む)。
 * `available`: いま存在する文書のパス。なくなった文書は、履歴と最近使った順から外す。
 * 復元できる window が 1 つもなければ null。
 */
export function restoreModel(
  snapshot: SessionSnapshot,
  available: ReadonlySet<string>,
): Model | null {
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
    mru: snapshot.mru.filter((p) => available.has(p)),
    winSeq: Math.max(snapshot.winSeq, ...ids),
    root,
    selected: ids.includes(snapshot.selected) ? snapshot.selected : (ids[0] ?? 1),
  };
}

/** 復元した model が表示に使う文書(履歴にあるすべて)のパス。 */
export function referencedPaths(model: Model): string[] {
  const out = new Set<string>();
  const walk = (n: LayoutNode): void => {
    if (n.type === "leaf") n.win.history.forEach((e) => out.add(e.path));
    else n.children.forEach(walk);
  };
  walk(model.root);
  return [...out];
}
