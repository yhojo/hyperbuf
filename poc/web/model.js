// 操作モデル(docs/interaction-model.md)。DOM やシェルに依存しない純粋なロジック。

export function slugify(text) {
  return text
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s_-]/gu, "")
    .replace(/\s+/g, "-");
}

export function parseHeadings(text) {
  const headings = [];
  const seen = new Map();
  let inFence = false;
  for (const line of text.split("\n")) {
    if (/^```/.test(line)) inFence = !inFence;
    if (inFence) continue;
    const m = /^(#{1,6})\s+(.*)$/.exec(line);
    if (!m) continue;
    const base = slugify(m[2]);
    const n = seen.get(base) ?? 0;
    seen.set(base, n + 1);
    headings.push({ level: m[1].length, text: m[2], id: n === 0 ? base : `${base}-${n}` });
  }
  return headings;
}

// href を現在の文書からの相対で解決する。外部 URL は null。
export function resolveLink(fromPath, href) {
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) return null;
  const [pathPart, anchor = null] = href.split("#");
  if (pathPart === "") return { path: fromPath, anchor };
  const parts = fromPath.split("/").slice(0, -1);
  for (const seg of pathPart.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") parts.pop();
    else parts.push(seg);
  }
  return { path: parts.join("/"), anchor };
}

export function createModel() {
  const model = { buffers: new Map(), mru: [], winSeq: 0, root: null, selected: null };
  const win = makeWindow(model);
  model.root = leaf(win);
  model.selected = win.id;
  return model;
}

function makeWindow(model, from = null) {
  return {
    id: ++model.winSeq,
    history: from ? from.history.map((e) => ({ ...e })) : [],
    index: from ? from.index : -1,
  };
}

const leaf = (win) => ({ type: "leaf", win });

export function windows(model) {
  const out = [];
  (function walk(node) {
    if (node.type === "leaf") out.push(node.win);
    else node.children.forEach(walk);
  })(model.root);
  return out;
}

export const selectedWindow = (model) => windows(model).find((w) => w.id === model.selected);
export const currentEntry = (win) => win.history[win.index] ?? null;

export function openBuffer(model, path, text) {
  const buf = model.buffers.get(path) ?? { path, text: "", headings: [], version: 0 };
  buf.text = text;
  buf.headings = parseHeadings(text);
  buf.version += 1;
  model.buffers.set(path, buf);
  return buf;
}

function touch(model, path) {
  model.mru = [path, ...model.mru.filter((p) => p !== path)];
}

// buffer 切替(C-x b)・リンク・見出しジャンプはすべて履歴に積む。
export function visit(model, win, path, anchor = null) {
  const cur = currentEntry(win);
  if (cur && cur.path === path && cur.anchor === anchor) return;
  win.history.splice(win.index + 1);
  win.history.push({ path, anchor, scroll: 0 });
  win.index = win.history.length - 1;
  touch(model, path);
}

export function back(model, win) {
  if (win.index <= 0) return false;
  win.index -= 1;
  touch(model, currentEntry(win).path);
  return true;
}

export function forward(model, win) {
  if (win.index >= win.history.length - 1) return false;
  win.index += 1;
  touch(model, currentEntry(win).path);
  return true;
}

function findParent(node, target, parent = null) {
  if (node === target) return parent;
  if (node.type === "split") {
    for (const child of node.children) {
      const found = findParent(child, target, node);
      if (found) return found;
    }
  }
  return null;
}

function nodeOf(model, win) {
  let found = null;
  (function walk(node) {
    if (node.type === "leaf") {
      if (node.win === win) found = node;
    } else node.children.forEach(walk);
  })(model.root);
  return found;
}

// dir: "col"(上下に並べる = C-x 2) / "row"(左右に並べる = C-x 3)
// 新しい window には分割元の履歴を複製する。選択は分割元のまま。
export function split(model, dir) {
  const win = selectedWindow(model);
  const node = nodeOf(model, win);
  const fresh = makeWindow(model, win);
  const replacement = { type: "split", dir, children: [leaf(win), leaf(fresh)] };
  const parent = findParent(model.root, node);
  if (!parent) model.root = replacement;
  else parent.children[parent.children.indexOf(node)] = replacement;
  return fresh;
}

export function deleteWindow(model) {
  const win = selectedWindow(model);
  const node = nodeOf(model, win);
  const parent = findParent(model.root, node);
  if (!parent) return false;
  const sibling = parent.children.find((c) => c !== node);
  const grand = findParent(model.root, parent);
  if (!grand) model.root = sibling;
  else grand.children[grand.children.indexOf(parent)] = sibling;
  model.selected = firstLeaf(sibling).win.id;
  return true;
}

function firstLeaf(node) {
  return node.type === "leaf" ? node : firstLeaf(node.children[0]);
}

export function deleteOthers(model) {
  model.root = leaf(selectedWindow(model));
}

export function otherWindow(model) {
  const all = windows(model);
  const i = all.findIndex((w) => w.id === model.selected);
  model.selected = all[(i + 1) % all.length].id;
}
