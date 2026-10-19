// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { createRenderer } from "../src/pipeline.ts";

const renderer = await createRenderer();
const ctx = { docPath: "/p/docs/a.md", resolveResource: (p: string) => `res://${p}` };
const html = (md: string, docPath = ctx.docPath) =>
  renderer.renderMarkdown(md, { ...ctx, docPath }).html;
const fixture = (name: string) =>
  readFileSync(new URL(`../../fixtures/sample-project/rendering/${name}`, import.meta.url), "utf8");

test("sanitize: removes script, event handlers and javascript: URLs", () => {
  const out = html(
    [
      "<script>alert(1)</script>",
      '<img src="x.png" onerror="alert(1)">',
      '<a href="javascript:alert(1)">x</a>',
      '<iframe src="https://example.com"></iframe>',
      '<div onclick="alert(1)" style="position:fixed">d</div>',
      "[md](javascript:alert(1))",
    ].join("\n\n"),
  );
  assert.doesNotMatch(out, /<script|onerror|onclick|javascript:|<iframe|style=/i);
});

test("sanitize: the security fixtures leave no execution, external loading or DOM clobbering", () => {
  const out = html(fixture("06-html-security.md"), "rendering/06-html-security.md");
  assert.doesNotMatch(out, /<(script|iframe|object|embed|form|style|meta|base|svg|button)\b/i);
  // Only the disabled checkboxes for task lists remain as input (no input or submission possible)
  for (const input of out.match(/<input\b[^>]*>/gi) ?? []) {
    assert.match(input, /type="checkbox"/);
    assert.match(input, /\bdisabled\b/);
  }
  assert.doesNotMatch(out, /\son[a-z]+\s*=/i); // onclick, onerror, onload, ...
  assert.doesNotMatch(out, /\b(href|src|action|data)\s*=\s*["']?\s*javascript:/i); // attributes only (words in the body text are not covered)
  assert.doesNotMatch(out, /style=/i);
  // ids that could collide with the app's DOM are isolated by a prefix
  assert.doesNotMatch(out, /\sid="echo"/);
  assert.match(out, /id="user-content-echo"/);
  // the document is rendered to its end
  assert.match(out, /最後まで表示されれば OK です/);
});

test("GFM: tables, task lists, strikethrough, autolinks, footnotes", () => {
  const out = html(
    "| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n\n~~del~~ https://example.com\n\nfoot[^1]\n\n[^1]: note\n",
  );
  assert.match(out, /<table/);
  assert.match(out, /type="checkbox"/);
  assert.match(out, /<del>del<\/del>/);
  assert.match(out, /<a href="https:\/\/example.com"/);
  assert.match(out, /footnote/i);
});

test("footnotes: link target ids do not get a double prefix", () => {
  const out = html("foot[^1]\n\n[^1]: note\n");
  assert.match(out, /href="#fn-1"/);
  assert.match(out, /id="user-content-fn-1"/);
  assert.doesNotMatch(out, /user-content-user-content/);
});

test("ids/names in raw HTML get a prefix so they do not collide with the app's DOM", () => {
  assert.match(html('<a name="echo" id="echo">x</a>'), /id="user-content-echo"/);
});

test("heading IDs follow GitHub's scheme, and sanitize adds the prefix", () => {
  const out = html("# Hello, World!\n\n## Hello, World!\n\n## 日本語 見出し\n");
  assert.match(out, /id="user-content-hello-world"/);
  assert.match(out, /id="user-content-hello-world-1"/);
  assert.match(out, /id="user-content-日本語-見出し"/);
});

test("math: rendered with KaTeX; an invalid expression shows an error without stopping", () => {
  const out = html("inline $a^2+b^2$ and\n\n$$\n\\frac{1}{2}\n$$\n\nbroken $\\unknowncmd{$ here\n");
  assert.match(out, /class="katex"/);
  assert.match(out, /katex-display/);
});

test('math: as on GitHub, currency like "$5 to $10" is not treated as math', () => {
  assert.doesNotMatch(html("価格は $5 から $10 です。"), /class="katex"/);
  assert.doesNotMatch(html("a $ b $ c"), /class="katex"/);
  assert.match(html("式 $x+1$ です"), /class="katex"/);
});

test("code: starry-night colors with pl-* classes; unknown languages pass through", () => {
  const out = html("```js\nconst x = 1;\n```\n\n```unknownlang\nplain\n```\n");
  assert.match(out, /pl-k/);
  assert.match(out, /plain/);
});

test("Mermaid blocks are only marked", () => {
  assert.match(html("```mermaid\ngraph TD; A-->B\n```\n"), /class="mermaid-source"/);
});

test("images: relative paths are rewritten and external URLs are not loaded", () => {
  const out = html("![a](img/x.svg) ![b](https://example.com/p.png) ![c](../up.png)");
  assert.match(out, /src="res:\/\/\/p\/docs\/img\/x\.svg"/);
  assert.match(out, /src="res:\/\/\/p\/up\.png"/);
  assert.doesNotMatch(out, /example\.com\/p\.png/);
  assert.match(out, /blocked-image/);
});

test("line anchors: block elements carry the original line number", () => {
  const out = html("# 見出し\n\n段落1\n\n- a\n- b\n\n```js\ncode\n```\n");
  assert.match(out, /<h1[^>]*data-source-line="1"/);
  assert.match(out, /<p data-source-line="3"/);
  assert.match(out, /<li data-source-line="5"/);
  assert.match(out, /<li data-source-line="6"/);
  assert.match(out, /<pre data-source-line="8"/);
});

test("source position: block elements carry start / end offsets and lines", () => {
  const md = "# 見出し\n\n段落 A\n段落 B\n\n- x\n";
  const out = html(md);
  // heading: 0 to 5 ("# 見出し" is 5 characters), line 1
  assert.match(out, /<h1[^>]*data-source-start="0"[^>]*data-source-end="5"/);
  // paragraph: 7 to 15 ("段落 A\n段落 B"), lines 3-4
  const p =
    /<p[^>]*data-source-start="(\d+)"[^>]*data-source-end="(\d+)"[^>]*data-source-end-line="(\d+)"/.exec(
      out,
    );
  assert.ok(p, out);
  assert.equal(md.slice(Number(p[1]), Number(p[2])), "段落 A\n段落 B");
  assert.equal(p[3], "4");
});

test("alerts", () => {
  const out = html("> [!WARNING]\n> careful\n");
  assert.match(out, /markdown-alert-warning/);
  assert.match(out, /markdown-alert-title/);
});

test("details/summary and kbd pass through", () => {
  const out = html("<details><summary>s</summary>body</details>\n\n<kbd>C-x</kbd>");
  assert.match(out, /<details/);
  assert.match(out, /<kbd>/);
});

test("math: Marked 2 style, renders \\_ as a subscript (can be left as is via a setting)", () => {
  const md = "$f\\_{2}$ と $$ g\\_{1} = \\text{a\\_b} $$";
  const on = html(md);
  assert.match(on, /msupsub/); // becomes a subscript
  assert.match(on, /a_b/); // inside \text, the underscore stays a literal character
  renderer.configure({ mathUnescapeUnderscore: false });
  try {
    const off = html("$f\\_{2}$");
    assert.doesNotMatch(off, /msupsub/); // left as is, it is an underscore character
  } finally {
    renderer.configure({ mathUnescapeUnderscore: true });
  }
});

test("syntax highlighting: Emacs Lisp is colored after prepare; unknown languages pass through", async () => {
  const md = '```elisp\n(defun foo (x) "doc" (+ x 1))\n```\n\n```nosuchlang\n(defun foo)\n```\n';
  assert.ok(!html(md).includes("pl-k"), "not colored before prepare (lazy loading)");
  await renderer.prepare(md);
  const out = html(md);
  assert.match(out, /<span class="pl-k">defun<\/span>/);
  assert.ok(!out.includes("nosuchlang</span>"));
  assert.match(
    html("```clojure\n(defn f [x] x)\n```"),
    /pl-/,
    "small grammars are always included",
  );
});

test("math: the KaTeX used for rendering matches the bundled CSS version (mismatched class names break subscripts and fractions)", () => {
  const css = readFileSync(
    new URL("../node_modules/katex/dist/katex.min.css", import.meta.url),
    "utf8",
  );
  const out = html("$x_1^2 + \\frac{1}{2}$");
  const classes = new Set(
    [...out.matchAll(/class="([^"]+)"/g)].flatMap((m) => (m[1] as string).split(" ")),
  );
  for (const c of ["sizing", "msupsub", "vlist-t", "mfrac", "reset-size6"]) {
    assert.ok(classes.has(c), `output lacks ${c}`);
    assert.ok(css.includes(`.${c}`), `CSS lacks .${c} (katex versions are mismatched)`);
  }
});

test("math: a single-line $$ … $$ is also display math (centered); $ … $ stays inline", () => {
  const single = html("$$ f_1 = \\frac{1}{2} $$");
  assert.match(single, /katex-display/);
  const inline = html("文中の $x_1$ です");
  assert.ok(!inline.includes("katex-display"));
  assert.ok(html("a $$x$$ b").includes("katex-display"));
});
