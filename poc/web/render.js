// PoC 用の最小 Markdown レンダラー。本番のレンダリング(docs/architecture-evaluation.md)とは別物。
// 入力は信頼できないものとして扱い、すべてエスケープする。生 HTML は通さない。

import { parseHeadings } from "./model.js";

const esc = (s) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

function safeHref(href) {
  return /^(https?:|mailto:|#|[^:]*$)/i.test(href) ? href : "#";
}

function inline(text) {
  let out = esc(text);
  out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
  out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  out = out.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, href) => {
    const h = safeHref(href.replace(/&amp;/g, "&"));
    return `<a href="${esc(h)}">${label}</a>`;
  });
  return out;
}

export function renderMarkdown(text) {
  const headings = parseHeadings(text);
  let hi = 0;
  const html = [];
  let list = false;
  let fence = null;
  let para = [];

  const flushPara = () => {
    if (para.length) html.push(`<p>${inline(para.join(" "))}</p>`);
    para = [];
  };
  const closeList = () => {
    if (list) html.push("</ul>");
    list = false;
  };

  for (const line of text.split("\n")) {
    if (fence !== null) {
      if (/^```/.test(line)) {
        html.push(`<pre><code>${esc(fence.join("\n"))}</code></pre>`);
        fence = null;
      } else fence.push(line);
      continue;
    }
    if (/^```/.test(line)) {
      flushPara();
      closeList();
      fence = [];
      continue;
    }
    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) {
      flushPara();
      closeList();
      const info = headings[hi++];
      html.push(`<h${h[1].length} id="${esc(info.id)}">${inline(h[2])}</h${h[1].length}>`);
      continue;
    }
    const li = /^\s*[-*]\s+(.*)$/.exec(line);
    if (li) {
      flushPara();
      if (!list) html.push("<ul>");
      list = true;
      html.push(`<li>${inline(li[1])}</li>`);
      continue;
    }
    if (line.trim() === "") {
      flushPara();
      closeList();
      continue;
    }
    closeList();
    para.push(line.trim());
  }
  flushPara();
  closeList();
  if (fence !== null) html.push(`<pre><code>${esc(fence.join("\n"))}</code></pre>`);
  return html.join("\n");
}
