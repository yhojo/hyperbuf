// 操作モデル(docs/interaction-model.md)。DOM やシェルに依存しない純粋なロジック。

import { parseVirtualPath } from "./names.ts";
import { dirname, joinPath } from "./paths.ts";

export interface Buffer {
  readonly path: string;
  text: string;
  /** 内容が更新されるたびに増える。描画のやり直しの判定に使う。 */
  version: number;
  /** ファイルが削除された(または移動された)。バッファは残し、ヘッダに知らせる。 */
  missing?: boolean;
}

export interface HistoryEntry {
  path: string;
  anchor: string | null;
  scroll: number;
}

export interface Win {
  readonly id: number;
  history: HistoryEntry[];
  index: number;
}

export type SplitDirection = "row" | "col";

export type LayoutNode =
  | { type: "leaf"; win: Win }
  | { type: "split"; dir: SplitDirection; children: [LayoutNode, LayoutNode] };

export interface Model {
  buffers: Map<string, Buffer>;
  /** 最近使った順の buffer のパス。参照履歴とは別に管理する。 */
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
 * href を現在の文書(絶対パス)からの相対で解決して、絶対パスにする。外部 URL は null。
 * `/` で始まる href は、ファイルシステムの絶対パスとして扱う(プロジェクトという単位がないため)。
 */
export function resolveLink(fromPath: string, href: string): LinkTarget | null {
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) return null;
  const hash = href.indexOf("#");
  const pathPart = hash < 0 ? href : href.slice(0, hash);
  const anchor = hash < 0 ? null : href.slice(hash + 1);
  if (pathPart === "") return { path: fromPath, anchor };
  // リンクの URL は、パーセントエンコードされている(日本語のファイル名など)ので、戻す
  let decoded = pathPart;
  try {
    decoded = decodeURIComponent(pathPart);
  } catch {
    // 不正なエンコードは、そのまま使う
  }
  // 仮想 buffer(検索結果など)からの相対リンクは、起点のディレクトリ(なければ `/`)からとする
  const base = isVirtualPath(fromPath)
    ? (parseVirtualPath(fromPath).dir ?? "/")
    : dirname(fromPath);
  return { path: joinPath(base, decoded), anchor };
}

/** ファイルに対応しない buffer(`*search: …*` など)のパスか。実在の `.md` のパスは、`*` で終わらない。 */
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
  if (!win) throw new Error("選択中の window がありません");
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

/** buffer 切替(C-x b)・リンク・見出しジャンプはすべて履歴に積む。 */
export function visit(model: Model, win: Win, path: string, anchor: string | null = null): void {
  const cur = currentEntry(win);
  if (cur && cur.path === path && cur.anchor === anchor) return;
  win.history.splice(win.index + 1);
  win.history.push({ path, anchor, scroll: 0 });
  win.index = win.history.length - 1;
  touch(model, path);
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
  if (!found) throw new Error("window がレイアウトにありません");
  return found;
}

function firstLeaf(node: LayoutNode): Extract<LayoutNode, { type: "leaf" }> {
  return node.type === "leaf" ? node : firstLeaf(node.children[0]);
}

function replaceChild(parent: LayoutNode, old: LayoutNode, next: LayoutNode): void {
  if (parent.type !== "split") throw new Error("split ではありません");
  parent.children[parent.children[0] === old ? 0 : 1] = next;
}

/**
 * dir: "col"(上下に並べる = C-x 2) / "row"(左右に並べる = C-x 3)。
 * 新しい window には分割元の履歴を複製する。選択は分割元のまま。
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

export function deleteWindow(model: Model): boolean {
  return removeWindow(model, selectedWindow(model));
}

/** window を取り除き、分割をたたむ。唯一の window は取り除けない(false)。選択中のものなら、隣に移る。 */
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
 * buffer を閉じる。どの window の履歴からも、その buffer への参照を取り除く
 * (閉じた buffer を、Back / Forward で表示できなくなる、という状態を作らない)。
 * 閉じた buffer を表示していた window は、履歴の、ひとつ前の参照を表示する。
 * @returns 履歴が空になった window(表示するものがないので、呼び出し側が、別の buffer を開く)。
 */
export function killBuffer(model: Model, path: string): Win[] {
  model.buffers.delete(path);
  model.mru = model.mru.filter((p) => p !== path);
  const empty: Win[] = [];
  for (const win of windows(model)) {
    // 現在位置(index)より前に残る参照の数から、新しい index を求める
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
