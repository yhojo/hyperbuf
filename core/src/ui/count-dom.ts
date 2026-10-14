// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 表示されているテキストの取り出し(`count-words`)。選択があれば選択範囲、なければ文書全体。
//
// `innerText` や `selection.toString()` は、レイアウトに依存し、数式(KaTeX の表レイアウト)の途中に改行を挟むので使わない。
// 要素の種類(タグ)で、ブロックの区切りを判断する。レイアウトに触れないので、選択の複製(断片)にも使える。

/** 前後で、行を区切る要素。 */
const BLOCKS = new Set([
  "ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "DD", "DETAILS", "DIV", "DL", "DT", "FIELDSET",
  "FIGCAPTION", "FIGURE", "FOOTER", "H1", "H2", "H3", "H4", "H5", "H6", "HEADER", "HR", "LI",
  "MAIN", "NAV", "OL", "P", "PRE", "SECTION", "SUMMARY", "TABLE", "TR", "UL",
]); // prettier-ignore

/** 数えない要素(図は、散文ではない。画像の代替テキストは、表示されない)。 */
const SKIPPED = new Set(["SVG", "SCRIPT", "STYLE", "IMG", "CANVAS"]);

/**
 * ルート(要素・断片)の中の、表示されるテキスト。ブロックの間は改行、表のセルの間は空白で区切る。
 * `preformatted`: ルートが、コードブロック(`<pre>`)の中身であること(空白と改行を、そのまま残す)。
 */
export function extractText(root: Node, preformatted = false): string {
  let out = "";
  const newline = (): void => {
    if (out !== "" && !out.endsWith("\n")) out += "\n";
  };
  const walk = (node: Node, preformatted: boolean): void => {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.nodeValue ?? "";
      out += preformatted ? text : text.replace(/\s+/g, " ");
      return;
    }
    if (node.nodeType !== Node.ELEMENT_NODE && node.nodeType !== Node.DOCUMENT_FRAGMENT_NODE)
      return;
    const el = node as Element;
    const tag = node.nodeType === Node.ELEMENT_NODE ? el.tagName.toUpperCase() : "";
    if (SKIPPED.has(tag)) return;
    if (tag === "BR") return void newline();
    // 数式: 見える HTML の部分だけを、1 つながりのテキストとして読む(読み上げ用の MathML は、重複するので読まない)
    if (el.classList?.contains("katex")) {
      out += el.querySelector(".katex-html")?.textContent ?? "";
      return;
    }
    const block = BLOCKS.has(tag) || el.classList?.contains("katex-display");
    if (block) newline();
    for (const child of node.childNodes) walk(child, preformatted || tag === "PRE");
    if (block) newline();
    else if (tag === "TD" || tag === "TH") out += " ";
  };
  walk(root, preformatted);
  return out;
}

/**
 * window の本文から、数える対象のテキストを取り出す。
 * @returns 範囲(選択がこの window の本文の中にあれば `Region`、なければ文書全体の `Buffer`)とテキスト。文書がなければ null
 */
export function displayedText(
  content: HTMLElement,
): { scope: "Region" | "Buffer"; text: string } | null {
  const body = content.querySelector<HTMLElement>(".markdown-body");
  if (!body) return null;
  const selection = window.getSelection();
  if (selection && !selection.isCollapsed && selection.rangeCount > 0) {
    const range = selection.getRangeAt(0);
    if (content.contains(range.commonAncestorContainer)) {
      // 選択がコードブロックの中だけにあるとき、複製した断片には `<pre>` がないので、ここで判断する
      const ancestor = range.commonAncestorContainer;
      const element = ancestor instanceof Element ? ancestor : ancestor.parentElement;
      const inCode = element?.closest("pre") != null;
      return { scope: "Region", text: extractText(range.cloneContents(), inCode) };
    }
  }
  return { scope: "Buffer", text: extractText(body) };
}
