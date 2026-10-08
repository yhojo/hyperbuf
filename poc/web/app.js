import {
  createModel, openBuffer, visit, back, forward, split, deleteWindow, deleteOthers,
  otherWindow, windows, selectedWindow, currentEntry, resolveLink,
} from "./model.js";
import { keyName, createKeymap, createDispatcher } from "./keys.js";
import { fuzzyFilter } from "./fuzzy.js";
import { createRenderer, hydrateDiagrams, findAnchor } from "./pipeline.js";
import onigWasm from "vscode-oniguruma/release/onig.wasm";
import "github-markdown-css/github-markdown.css";
import "katex/dist/katex.min.css";
import "@wooorm/starry-night/style/both";
import "./style.css";
import { getHost } from "./host.js";

const $ = (id) => document.getElementById(id);
const frameEl = $("frame");
const echoEl = $("echo");
const statusEl = $("status");

const host = getHost();
const renderer = await createRenderer({ onigUrl: new URL(onigWasm, import.meta.url) });
const model = createModel();
const winEls = new Map(); // window id -> { el, content, header, lastEntry, linkIndex }

// ---------------------------------------------------------------- キーマップ
const keymap = createKeymap({
  "C-x 2": "split-below",
  "C-x 3": "split-right",
  "C-x 0": "delete-window",
  "C-x 1": "delete-other-windows",
  "C-x o": "other-window",
  "C-x b": "switch-buffer",
  "C-x C-f": "find-file",
  "M-x": "execute-command",
  "C-f": "forward",
  "C-b": "back",
  "s-]": "forward",
  "s-[": "back",
  "C-n": "scroll-line-down",
  "C-p": "scroll-line-up",
  "C-v": "scroll-page-down",
  "M-v": "scroll-page-up",
  "TAB": "next-link",
  "S-TAB": "prev-link",
  "RET": "follow-link",
  "C-c j": "goto-heading",
  "M-s g": "search-project",
  "M-g g": "goto-line",
  "C-g": "keyboard-quit",
});
const dispatcher = createDispatcher(keymap);

// ---------------------------------------------------------------- コマンド
const sel = () => selectedWindow(model);
const ui = () => winEls.get(sel().id);

async function ensureBuffer(path) {
  if (model.buffers.has(path)) return;
  openBuffer(model, path, await host.readFile(path));
}

async function follow(win, href) {
  const buf = model.buffers.get(currentEntry(win).path);
  const target = resolveLink(buf.path, href);
  if (!target) return echo(`外部リンクは PoC では開きません: ${href}`);
  try {
    await ensureBuffer(target.path);
  } catch (err) {
    return echo(`開けません: ${target.path} (${err.message})`);
  }
  visit(model, win, target.path, target.anchor);
}

const scrollBy = (dy) => ui().content.scrollBy({ top: dy });

function moveLink(dir) {
  const u = ui();
  const links = [...u.content.querySelectorAll("a")];
  if (!links.length) return;
  u.linkIndex = u.linkIndex < 0 ? (dir > 0 ? 0 : links.length - 1) : (u.linkIndex + dir + links.length) % links.length;
  links.forEach((a, i) => a.classList.toggle("link-focus", i === u.linkIndex));
  links[u.linkIndex].scrollIntoView({ block: "nearest" });
}

// プロジェクト内の全文検索。結果は仮想 buffer(`*search: …*`)に Markdown として並べ、リンクで該当行へ飛ぶ。
async function searchProject(query) {
  if (!host.search) return echo("このホストは全文検索に対応していません");
  const t0 = performance.now();
  const res = await host.search(query, { limit: 500 });
  if (res.error) return echo(`検索に失敗: ${res.error}`);
  const lines = [`# 検索: ${query.replace(/[`#]/g, "")}`, "", `${res.total} 件${res.truncated ? "(先頭 " + res.results.length + " 件を表示)" : ""}`, ""];
  for (const r of res.results) {
    const snippet = r.text.trim().replace(/`/g, "'");
    lines.push(`- [${r.path.replace(/[\[\]]/g, "")}:${r.line}](${encodeURI(r.path)}#line:${r.line}) \`${snippet}\``);
  }
  const vpath = `*search: ${query}*`;
  openBuffer(model, vpath, lines.join("\n"));
  visit(model, sel(), vpath);
  echo(`検索 ${res.total} 件 (${(performance.now() - t0).toFixed(0)}ms、ホスト ${(res.listMs + res.scanMs).toFixed(0)}ms)`);
}

const commands = {
  "split-below": () => split(model, "col"),
  "split-right": () => split(model, "row"),
  "delete-window": () => deleteWindow(model) || echo("これが唯一の window です"),
  "delete-other-windows": () => deleteOthers(model),
  "other-window": () => otherWindow(model),
  "back": () => back(model, sel()) || echo("これより前の履歴はありません"),
  "forward": () => forward(model, sel()) || echo("これより先の履歴はありません"),
  "scroll-line-down": () => scrollBy(48),
  "scroll-line-up": () => scrollBy(-48),
  "scroll-page-down": () => scrollBy(ui().content.clientHeight * 0.9),
  "scroll-page-up": () => scrollBy(-ui().content.clientHeight * 0.9),
  "next-link": () => moveLink(1),
  "prev-link": () => moveLink(-1),
  "follow-link": async () => {
    const u = ui();
    const a = u.content.querySelectorAll("a")[u.linkIndex];
    if (a) await follow(sel(), a.getAttribute("href"));
  },
  "switch-buffer": async () => {
    const path = await prompt("Switch to buffer: ", model.mru, false);
    if (path) visit(model, sel(), path);
  },
  "find-file": async () => {
    const path = await prompt("Find file: ", await host.listFiles());
    if (!path) return;
    try {
      await ensureBuffer(path);
      visit(model, sel(), path);
    } catch (err) {
      echo(`開けません: ${path} (${err.message})`);
    }
  },
  "goto-heading": async () => {
    // 見出しは描画後の DOM から取る(id は GitHub 方式で付くので、正規表現による解析とはずれ得る)
    const buf = model.buffers.get(currentEntry(sel()).path);
    const headings = [...ui().content.querySelectorAll("h1,h2,h3,h4,h5,h6")].map((h) => ({
      level: Number(h.tagName[1]),
      text: h.textContent,
      id: h.id.replace(/^user-content-/, ""),
    }));
    const items = headings.map((h) => `${"  ".repeat(h.level - 1)}${h.text}`);
    const picked = await prompt("Heading: ", items, false);
    if (picked) visit(model, sel(), buf.path, headings[items.indexOf(picked)].id);
  },
  // プロジェクト内の全文検索。結果は仮想 buffer(`*search: …*`)に Markdown として並べ、リンクで該当行へ飛ぶ。
  "search-project": async () => {
    const query = await prompt("Search project: ", []);
    if (query) await searchProject(query);
  },
  "goto-line": async () => {
    const n = Number(await prompt("Goto line: ", []));
    if (Number.isInteger(n) && n > 0) visit(model, sel(), currentEntry(sel()).path, `line:${n}`);
  },
  "execute-command": async () => {
    const name = await prompt("M-x ", Object.keys(commands), false);
    if (name) await commands[name]();
  },
  "keyboard-quit": () => echo("Quit"),
};
if (host.simulateChange) {
  commands["simulate-external-change"] = () => host.simulateChange(currentEntry(sel()).path);
}

// ---------------------------------------------------------------- ミニバッファ
let prompting = false;

function prompt(label, candidates = [], allowFree = true) {
  return new Promise((resolve) => {
    prompting = true;
    const mini = $("minibuffer");
    const input = $("prompt-input");
    const list = $("candidates");
    $("prompt-label").textContent = label;
    input.value = "";
    mini.hidden = false;
    input.focus();
    let shown = [];
    let on = 0;

    const update = () => {
      shown = fuzzyFilter(candidates, input.value, 8);
      on = Math.min(on, Math.max(0, shown.length - 1));
      list.replaceChildren(
        ...shown.map((c, i) => Object.assign(document.createElement("li"), { textContent: c, className: i === on ? "on" : "" })),
      );
    };
    const done = (value) => {
      prompting = false;
      mini.hidden = true;
      input.removeEventListener("keydown", onKey);
      input.removeEventListener("input", onInput);
      input.blur();
      resolve(value);
    };
    const onInput = () => {
      on = 0;
      update();
    };
    // ここで扱うのは確定・取消・候補選択だけ。C-f/C-b/C-a/C-e などは WebView 既定の文字移動に任せる。
    const onKey = (e) => {
      const name = keyName(e);
      if (name === "RET") {
        e.preventDefault();
        done(shown[on] ?? (allowFree && input.value ? input.value : null));
      } else if (name === "C-g" || name === "ESC") {
        e.preventDefault();
        done(null);
      } else if (name === "C-n" || name === "down") {
        e.preventDefault();
        on = Math.min(on + 1, shown.length - 1);
        update();
      } else if (name === "C-p" || name === "up") {
        e.preventDefault();
        on = Math.max(on - 1, 0);
        update();
      } else if (name === "TAB") {
        e.preventDefault();
        if (shown[on]) {
          input.value = shown[on];
          update();
        }
      }
    };
    input.addEventListener("keydown", onKey);
    input.addEventListener("input", onInput);
    update();
  });
}

// ---------------------------------------------------------------- 描画
function windowUi(win) {
  let u = winEls.get(win.id);
  if (u) return u;
  const el = document.createElement("section");
  el.className = "win";
  const header = document.createElement("div");
  header.className = "win-header";
  const content = document.createElement("div");
  content.className = "content";
  el.append(header, content);
  u = { el, header, content, lastEntry: null, lastKey: null, linkIndex: -1, expectScroll: null };
  content.addEventListener("scroll", () => {
    if (u.expectScroll !== null && Math.abs(content.scrollTop - u.expectScroll) < 1) return;
    u.expectScroll = null;
    const entry = currentEntry(win);
    if (entry) entry.scroll = content.scrollTop;
  });
  content.addEventListener("click", (e) => {
    model.selected = win.id;
    const a = e.target.closest("a");
    if (a) {
      e.preventDefault();
      follow(win, a.getAttribute("href")).then(refresh);
    } else refresh();
  });
  winEls.set(win.id, u);
  return u;
}

function setScroll(u, top) {
  u.expectScroll = top;
  u.content.scrollTop = top;
}

function visibleAnchor(content) {
  let best = null;
  for (const h of content.querySelectorAll("[id]")) {
    if (h.offsetTop <= content.scrollTop + 1) best = { id: h.id, delta: content.scrollTop - h.offsetTop };
  }
  return best;
}

const resolveResource = host.resolveResource ?? ((path) => path);
const renderStats = { ms: 0, diagrams: "" };

function updateWindow(win) {
  const u = windowUi(win);
  const entry = currentEntry(win);
  const buf = model.buffers.get(entry.path);
  const key = `${entry.path}@${buf.version}`;
  u.el.classList.toggle("selected", win.id === model.selected);
  u.header.textContent = `${win.id === model.selected ? "●" : "○"} ${entry.path}${entry.anchor ? "#" + entry.anchor : ""}   [履歴 ${win.index + 1}/${win.history.length}]`;

  const samePath = u.lastEntry && u.lastEntry.path === entry.path;
  if (u.lastKey !== key) {
    // 外部更新(同じ文書の版が変わった)なら、見出し基準で閲覧位置を維持する
    const reload = u.lastEntry === entry && samePath;
    const anchor = reload ? visibleAnchor(u.content) : null;
    const ratio = reload ? u.content.scrollTop / Math.max(1, u.content.scrollHeight) : 0;
    const { html, ms } = renderer.renderMarkdown(buf.text, { docPath: entry.path, resolveResource });
    renderStats.ms = ms;
    u.content.innerHTML = `<div class="markdown-body">${html}</div>`;
    u.linkIndex = -1;
    const token = (u.renderToken = (u.renderToken ?? 0) + 1);
    if (reload) {
      u.computeTop = () => {
        const target = anchor && u.content.querySelector(`#${CSS.escape(anchor.id)}`);
        return target ? target.offsetTop + anchor.delta : u.content.scrollHeight * ratio;
      };
      setScroll(u, u.computeTop());
      entry.scroll = u.content.scrollTop;
    }
    u.lastKey = key;
    if (!reload) u.lastEntry = null; // 新しい表示として位置を適用する
    // Mermaid は描画後に高さが変わるので、読み手が動かしていなければ位置を取り直す
    queueMicrotask(() => settleDiagrams(u, entry, token));
  }
  if (u.lastEntry !== entry) {
    const viaAnchor = !entry.scroll && entry.anchor;
    u.computeTop = viaAnchor ? () => findAnchor(u.content, entry.anchor)?.offsetTop ?? 0 : () => entry.scroll;
    setScroll(u, u.computeTop());
    entry.scroll = u.content.scrollTop;
    u.linkIndex = -1;
    u.lastEntry = entry;
  }
}

async function settleDiagrams(u, entry, token) {
  const before = u.content.scrollTop;
  const info = await hydrateDiagrams(u.content);
  if (token !== u.renderToken) return;
  renderStats.diagrams = info.count ? `図 ${info.count}件(${info.ms.toFixed(0)}ms${info.errors ? `, 失敗${info.errors}` : ""})` : "";
  if (u.content.scrollTop === before && u.computeTop) {
    setScroll(u, u.computeTop());
    entry.scroll = u.content.scrollTop;
  }
}

let layoutSig = "";
const signature = (node) =>
  node.type === "leaf" ? `w${node.win.id}` : `${node.dir}(${node.children.map(signature).join(",")})`;

function refresh() {
  const build = (node) => {
    if (node.type === "leaf") return windowUi(node.win).el;
    const el = document.createElement("div");
    el.className = `split ${node.dir}`;
    el.append(...node.children.map(build));
    return el;
  };
  // 分割構成が変わったときだけ DOM を付け替える。付け替えるとスクロール位置が失われるので、
  // そのときは全 window で保存済みの位置を適用し直す。
  const sig = signature(model.root);
  const relayout = sig !== layoutSig;
  if (relayout) {
    layoutSig = sig;
    frameEl.replaceChildren(build(model.root));
    const live = new Set(windows(model).map((w) => w.id));
    for (const id of winEls.keys()) if (!live.has(id)) winEls.delete(id);
  }
  for (const win of windows(model)) {
    const u = windowUi(win);
    if (relayout) u.lastEntry = null;
    updateWindow(win);
  }
}

function echo(msg) {
  echoEl.textContent = msg;
}

// ---------------------------------------------------------------- レイテンシ計測
const samples = [];
function recordLatency(t0, name) {
  requestAnimationFrame(() =>
    setTimeout(() => {
      const ms = performance.now() - t0;
      samples.push(ms);
      if (samples.length > 100) samples.shift();
      const sorted = [...samples].sort((a, b) => a - b);
      const q = (p) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
      statusEl.textContent =
        `${host.name} | ${name}: ${ms.toFixed(1)}ms (描画 ${renderStats.ms.toFixed(1)}ms ${renderStats.diagrams}) | 中央値 ${q(0.5).toFixed(1)} / p95 ${q(0.95).toFixed(1)} / 最大 ${sorted.at(-1).toFixed(1)} (n=${samples.length})`;
    }, 0),
  );
}

// ---------------------------------------------------------------- 入力
let queue = Promise.resolve();

window.addEventListener("keydown", async (e) => {
  if (prompting) return;
  const name = keyName(e);
  if (!name) return;
  const t0 = e.timeStamp;
  if (name === "C-g") {
    dispatcher.reset();
    e.preventDefault();
    echo("Quit");
    return;
  }
  const r = dispatcher.feed(name);
  if (r.type === "unbound") {
    if (r.keys.length > 1) {
      e.preventDefault();
      echo(`${r.keys.join(" ")} は未割り当てです`);
    }
    return; // 単独の未割り当てキーは WebView 既定に任せる(Cmd+C など)
  }
  e.preventDefault();
  if (r.type === "prefix") return echo(`${r.pending.join(" ")} -`);
  echo("");
  // 非同期コマンド(ファイル読み込みなど)の完了前に次のキーが処理されないよう、実行は直列にする
  queue = queue.then(async () => {
    try {
      await commands[r.command]();
    } catch (err) {
      echo(`${r.command}: ${err.message}`);
    }
    refresh();
    recordLatency(t0, `${name} → ${r.command}`);
  });
});

// ---------------------------------------------------------------- 起動
async function main() {
  const files = await host.listFiles();
  const first = files.includes("index.md") ? "index.md" : files[0];
  await ensureBuffer(first);
  visit(model, sel(), first);
  refresh();
  echo(`${files.length} files / host: ${host.name}`);
  host.onFileChanged(async (path) => {
    if (!model.buffers.has(path)) return;
    openBuffer(model, path, await host.readFile(path));
    refresh();
    echo(`外部更新を反映: ${path}`);
  });
}

main().catch((err) => echo(`起動に失敗: ${err.message}`));

// 自動検証用の入口(ヘッドレスで文書を開き、描画の統計を読む)
window.__hb = {
  model, commands, keymap, samples, renderStats, fuzzyFilter, searchProject, refresh,
  async open(path, anchor = null) {
    await ensureBuffer(path);
    visit(model, sel(), path, anchor);
    refresh();
  },
};
