// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Extracts the displayed text (`count-words`): the selection if any, otherwise the whole document.
//
// `innerText` and `selection.toString()` depend on layout and insert line breaks inside math (KaTeX table layout), so they are not used.
// Block boundaries are decided by element type (tag). This does not touch layout, so it also works on cloned selection fragments.

/** Elements that separate lines before and after. */
const BLOCKS = new Set([
  "ADDRESS", "ARTICLE", "ASIDE", "BLOCKQUOTE", "DD", "DETAILS", "DIV", "DL", "DT", "FIELDSET",
  "FIGCAPTION", "FIGURE", "FOOTER", "H1", "H2", "H3", "H4", "H5", "H6", "HEADER", "HR", "LI",
  "MAIN", "NAV", "OL", "P", "PRE", "SECTION", "SUMMARY", "TABLE", "TR", "UL",
]); // prettier-ignore

/** Elements not counted (diagrams are not prose; image alt text is not displayed). */
const SKIPPED = new Set(["SVG", "SCRIPT", "STYLE", "IMG", "CANVAS"]);

/**
 * Displayed text inside a root (element or fragment). Blocks are separated by newlines, table cells by spaces.
 * `preformatted`: the root is the contents of a code block (`<pre>`), so whitespace and newlines are kept as is.
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
    // Math: read only the visible HTML part as one run of text (the MathML for screen readers is duplicated, so it is skipped)
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
 * Extracts the text to count from a window's body.
 * @returns the range (`Region` if the selection is inside this window's body, otherwise the whole-document `Buffer`) and the text. null if there is no document
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
      // When the selection is only inside a code block, the cloned fragment has no `<pre>`, so decide here
      const ancestor = range.commonAncestorContainer;
      const element = ancestor instanceof Element ? ancestor : ancestor.parentElement;
      const inCode = element?.closest("pre") != null;
      return { scope: "Region", text: extractText(range.cloneContents(), inCode) };
    }
  }
  return { scope: "Buffer", text: extractText(body) };
}
