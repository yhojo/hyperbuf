// 文書内のインクリメンタル検索(C-s / C-r)。画面に表示された文書(DOM)の、文字列を検索する。
// 検索の判断は、../isearch.ts(純粋な関数)。ここは、文字列の索引・範囲・ハイライト・スクロール。
//
//  - 入力のたびに、一致を数え直し、基準の位置以降の最初の一致を選ぶ
//  - C-s で次、C-r で前(端で、反対の端へ。"Wrapped")。検索語が空のときの C-s は、前回の検索語を使う
//  - RET: その位置にとどまる(一致は、選択状態で残る)。C-g / ESC: 検索を始めた位置に戻る
//  - 大文字を含む検索語は、大文字小文字を区別する(それ以外は、区別しない)

import { findAll, firstMatch, isCaseSensitive, step } from "../isearch.ts";
import type { AppContext } from "./context.ts";

interface TextIndex {
  text: string;
  nodes: { node: Text; start: number }[];
}

/** 検索の対象にしない場所(数式の MathML の複製、図、スクリプト)。 */
const SKIP = ".katex-mathml, svg, script, style";
/** ブロックをまたぐ一致を作らないための、区切り。 */
const BLOCKS = "p,li,h1,h2,h3,h4,h5,h6,pre,td,th,blockquote,summary,dt,dd,div";
/** ハイライトする一致の上限(件数が多すぎると、重くなる)。 */
const HIGHLIGHT_LIMIT = 2000;

export function buildIndex(root: HTMLElement): TextIndex {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) =>
      n.parentElement?.closest(SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
  });
  let text = "";
  const nodes: TextIndex["nodes"] = [];
  let lastBlock: Element | null | undefined;
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const node = n as Text;
    if (!node.data) continue;
    const block = node.parentElement?.closest(BLOCKS) ?? null;
    if (lastBlock !== undefined && block !== lastBlock) text += "\n";
    lastBlock = block;
    nodes.push({ node, start: text.length });
    text += node.data;
  }
  return { text, nodes };
}

/** `offset` を含む(または、末尾が `offset` に等しい)テキストノード。 */
function nodeAt(index: TextIndex, offset: number): { node: Text; start: number } | null {
  let lo = 0;
  let hi = index.nodes.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if ((index.nodes[mid]?.start ?? Infinity) <= offset) lo = mid;
    else hi = mid - 1;
  }
  return index.nodes[lo] ?? null;
}

function rangeFor(index: TextIndex, start: number, end: number): Range | null {
  const a = nodeAt(index, start);
  const b = nodeAt(index, end - 1);
  if (!a || !b) return null;
  const range = document.createRange();
  range.setStart(a.node, start - a.start);
  range.setEnd(b.node, end - b.start);
  return range;
}

/** 画面の上端に、最初に見えているテキストの位置(検索を始める基準)。 */
function firstVisibleOffset(index: TextIndex, content: HTMLElement): number {
  const top = content.getBoundingClientRect().top;
  for (const { node, start } of index.nodes) {
    const rect = node.parentElement?.getBoundingClientRect();
    if (rect && rect.bottom > top + 1) return start;
  }
  return 0;
}

function highlights(): HighlightRegistry | null {
  return typeof CSS !== "undefined" && "highlights" in CSS && typeof Highlight !== "undefined"
    ? CSS.highlights
    : null;
}

function clearHighlights(): void {
  highlights()?.delete("hb-search");
  highlights()?.delete("hb-search-current");
}

function revealRange(content: HTMLElement, range: Range): void {
  const rect = range.getBoundingClientRect();
  const box = content.getBoundingClientRect();
  const margin = content.clientHeight * 0.15;
  if (rect.top < box.top + margin || rect.bottom > box.bottom - margin) {
    content.scrollTop += rect.top - box.top - content.clientHeight / 3;
  }
}

let lastQuery = "";

/** 文書内のインクリメンタル検索を始める。確定または取消まで、終わらない。 */
export async function startIsearch(ctx: AppContext, direction: 1 | -1): Promise<void> {
  const { minibuffer, views, echo } = ctx;
  const content = views.selected().content;
  const index = buildIndex(content);
  const origin = { scrollTop: content.scrollTop, from: firstVisibleOffset(index, content) };
  let dir: 1 | -1 = direction;
  let matches: number[] = [];
  let current: number | null = null;
  let query = "";

  const labelOf = (): string => (dir === 1 ? "I-search: " : "I-search backward: ");

  const select = (): void => {
    clearHighlights();
    const selection = window.getSelection();
    // ハイライトが使えるときは、選択に触れない(入力欄にフォーカスがあるときに選択を操作すると、
    // WKWebView は、入力欄のフォーカスを外す)
    if (!highlights()) selection?.removeAllRanges();
    if (current === null) return;
    const start = matches[current];
    const range = start === undefined ? null : rangeFor(index, start, start + query.length);
    if (!range) return;
    const registry = highlights();
    // 文書に選択を作ると、WKWebView は、ミニバッファの入力欄からフォーカスを奪い、以後のキー入力が
    // 届かなくなる。入力中は、ハイライトだけで示し、選択は、確定のあとに作る(ハイライトが使えない
    // 場合に限り、選択で代用する)
    if (!registry) selection?.addRange(range);
    revealRange(content, range);
    if (registry) {
      const all = matches
        .slice(0, HIGHLIGHT_LIMIT)
        .map((m) => rangeFor(index, m, m + query.length))
        .filter((r): r is Range => r !== null);
      registry.set("hb-search", new Highlight(...all));
      registry.set("hb-search-current", new Highlight(range));
    }
  };

  const show = (wrapped: boolean): void => {
    const counter =
      current === null
        ? query
          ? "Failing"
          : ""
        : `[${current + 1}/${matches.length}]${wrapped ? " Wrapped" : ""}`;
    session.setCount(counter);
    session.setLabel(`${current === null && query ? "Failing " : ""}${labelOf()}`);
    select();
  };

  const search = (text: string, anchor: number): void => {
    query = text;
    matches = findAll(index.text, query, isCaseSensitive(query));
    const first = firstMatch(matches, anchor, dir);
    current = first.index;
    show(first.wrapped);
  };

  const session = minibuffer.live(labelOf(), {
    onInput(text) {
      // 入力が変わったら、(いまの一致の位置、なければ、検索を始めた位置)から探し直す
      const anchor = current === null ? origin.from : (matches[current] ?? origin.from);
      search(text, anchor);
    },
    onKey(name) {
      if (name !== "C-s" && name !== "C-r") return false;
      dir = name === "C-s" ? 1 : -1;
      if (!query && lastQuery) {
        // 検索語が空のときは、前回の検索語を使う
        session.setText(lastQuery);
        search(lastQuery, origin.from);
        return true;
      }
      const next = step(matches.length, current, dir);
      current = next.index;
      show(next.wrapped);
      return true;
    },
  });

  const accepted = await session.done;
  clearHighlights();
  if (accepted && query) {
    lastQuery = query;
    // 一致は、選択状態で残す(そのまま、「エディタで編集」の対象にもなる)。ミニバッファの入力欄が、
    // フォーカスを失うときに、文書の選択を解除してしまう WebView があるので、閉じたあとで、選択し直す
    const start = current === null ? undefined : matches[current];
    const range = start === undefined ? null : rangeFor(index, start, start + query.length);
    if (range) {
      const selection = window.getSelection();
      selection?.removeAllRanges();
      selection?.addRange(range);
    }
  } else {
    window.getSelection()?.removeAllRanges();
    content.scrollTop = origin.scrollTop;
  }
  if (accepted && current === null && query) echo.message(`見つかりません: ${query}`);
}
