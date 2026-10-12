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

test("sanitize: script・イベントハンドラ・javascript: URL を除去する", () => {
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

test("sanitize: セキュリティ検証文書(fixtures)に、実行・外部読み込み・DOM の乗っ取りが残らない", () => {
  const out = html(fixture("06-html-security.md"), "rendering/06-html-security.md");
  assert.doesNotMatch(out, /<(script|iframe|object|embed|form|style|meta|base|svg|button)\b/i);
  // input は、タスクリスト用の「無効なチェックボックス」だけが残る(入力も送信もできない)
  for (const input of out.match(/<input\b[^>]*>/gi) ?? []) {
    assert.match(input, /type="checkbox"/);
    assert.match(input, /\bdisabled\b/);
  }
  assert.doesNotMatch(out, /\son[a-z]+\s*=/i); // onclick, onerror, onload, ...
  assert.doesNotMatch(out, /\b(href|src|action|data)\s*=\s*["']?\s*javascript:/i); // 属性の中だけ(本文の語は対象外)
  assert.doesNotMatch(out, /style=/i);
  // アプリの DOM と衝突しうる id は、接頭辞で隔離される
  assert.doesNotMatch(out, /\sid="echo"/);
  assert.match(out, /id="user-content-echo"/);
  // 文書の末尾まで描画される
  assert.match(out, /最後まで表示されれば OK です/);
});

test("GFM: 表・タスクリスト・取り消し線・自動リンク・脚注", () => {
  const out = html(
    "| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n\n~~del~~ https://example.com\n\nfoot[^1]\n\n[^1]: note\n",
  );
  assert.match(out, /<table/);
  assert.match(out, /type="checkbox"/);
  assert.match(out, /<del>del<\/del>/);
  assert.match(out, /<a href="https:\/\/example.com"/);
  assert.match(out, /footnote/i);
});

test("脚注: リンク先の id が二重に接頭辞付きにならない", () => {
  const out = html("foot[^1]\n\n[^1]: note\n");
  assert.match(out, /href="#fn-1"/);
  assert.match(out, /id="user-content-fn-1"/);
  assert.doesNotMatch(out, /user-content-user-content/);
});

test("raw HTML の id/name はアプリの DOM と衝突しないよう接頭辞が付く", () => {
  assert.match(html('<a name="echo" id="echo">x</a>'), /id="user-content-echo"/);
});

test("見出し ID は GitHub 方式で、sanitize が接頭辞を付ける", () => {
  const out = html("# Hello, World!\n\n## Hello, World!\n\n## 日本語 見出し\n");
  assert.match(out, /id="user-content-hello-world"/);
  assert.match(out, /id="user-content-hello-world-1"/);
  assert.match(out, /id="user-content-日本語-見出し"/);
});

test("数式: KaTeX で描画し、不正な式はエラー表示で止まらない", () => {
  const out = html("inline $a^2+b^2$ and\n\n$$\n\\frac{1}{2}\n$$\n\nbroken $\\unknowncmd{$ here\n");
  assert.match(out, /class="katex"/);
  assert.match(out, /katex-display/);
});

test("数式: GitHub と同じく「$5 から $10」の通貨表記は数式にしない", () => {
  assert.doesNotMatch(html("価格は $5 から $10 です。"), /class="katex"/);
  assert.doesNotMatch(html("a $ b $ c"), /class="katex"/);
  assert.match(html("式 $x+1$ です"), /class="katex"/);
});

test("コード: starry-night が pl-* クラスで着色し、未知の言語は素通し", () => {
  const out = html("```js\nconst x = 1;\n```\n\n```unknownlang\nplain\n```\n");
  assert.match(out, /pl-k/);
  assert.match(out, /plain/);
});

test("Mermaid ブロックには印だけを付ける", () => {
  assert.match(html("```mermaid\ngraph TD; A-->B\n```\n"), /class="mermaid-source"/);
});

test("画像: 相対パスは書き換え、外部 URL は読み込まない", () => {
  const out = html("![a](img/x.svg) ![b](https://example.com/p.png) ![c](../up.png)");
  assert.match(out, /src="res:\/\/\/p\/docs\/img\/x\.svg"/);
  assert.match(out, /src="res:\/\/\/p\/up\.png"/);
  assert.doesNotMatch(out, /example\.com\/p\.png/);
  assert.match(out, /blocked-image/);
});

test("行アンカー: ブロック要素に元の行番号が付く", () => {
  const out = html("# 見出し\n\n段落1\n\n- a\n- b\n\n```js\ncode\n```\n");
  assert.match(out, /<h1[^>]*data-source-line="1"/);
  assert.match(out, /<p data-source-line="3"/);
  assert.match(out, /<li data-source-line="5"/);
  assert.match(out, /<li data-source-line="6"/);
  assert.match(out, /<pre data-source-line="8"/);
});

test("元の位置: ブロック要素に、開始・終了のオフセットと行が付く", () => {
  const md = "# 見出し\n\n段落 A\n段落 B\n\n- x\n";
  const out = html(md);
  // 見出し: 0 〜 5(「# 見出し」は 5 文字)、1 行目
  assert.match(out, /<h1[^>]*data-source-start="0"[^>]*data-source-end="5"/);
  // 段落: 7 〜 15(「段落 A\n段落 B」)、3〜4 行目
  const p =
    /<p[^>]*data-source-start="(\d+)"[^>]*data-source-end="(\d+)"[^>]*data-source-end-line="(\d+)"/.exec(
      out,
    );
  assert.ok(p, out);
  assert.equal(md.slice(Number(p[1]), Number(p[2])), "段落 A\n段落 B");
  assert.equal(p[3], "4");
});

test("アラート", () => {
  const out = html("> [!WARNING]\n> careful\n");
  assert.match(out, /markdown-alert-warning/);
  assert.match(out, /markdown-alert-title/);
});

test("details/summary と kbd を通す", () => {
  const out = html("<details><summary>s</summary>body</details>\n\n<kbd>C-x</kbd>");
  assert.match(out, /<details/);
  assert.match(out, /<kbd>/);
});

test("数式: Marked 2 流に、\\_ を下付き文字として描画する(設定で、そのままにもできる)", () => {
  const md = "$f\\_{2}$ と $$ g\\_{1} = \\text{a\\_b} $$";
  const on = html(md);
  assert.match(on, /msupsub/); // 下付き文字になる
  assert.match(on, /a_b/); // \text の中は、文字としての下線のまま
  renderer.configure({ mathUnescapeUnderscore: false });
  try {
    const off = html("$f\\_{2}$");
    assert.doesNotMatch(off, /msupsub/); // そのままなら、下線の文字
  } finally {
    renderer.configure({ mathUnescapeUnderscore: true });
  }
});

test("シンタックスハイライト: Emacs Lisp は prepare のあとで着色され、未知の言語は素通し", async () => {
  const md = '```elisp\n(defun foo (x) "doc" (+ x 1))\n```\n\n```nosuchlang\n(defun foo)\n```\n';
  assert.ok(!html(md).includes("pl-k"), "prepare 前は着色されない(遅延読込)");
  await renderer.prepare(md);
  const out = html(md);
  assert.match(out, /<span class="pl-k">defun<\/span>/);
  assert.ok(!out.includes("nosuchlang</span>"));
  assert.match(html("```clojure\n(defn f [x] x)\n```"), /pl-/, "小さい文法は常時含める");
});

test("数式: 描画に使う KaTeX と、同梱する CSS の版が合っている(class 名が食い違うと、添字や分数が崩れる)", () => {
  const css = readFileSync(
    new URL("../node_modules/katex/dist/katex.min.css", import.meta.url),
    "utf8",
  );
  const out = html("$x_1^2 + \\frac{1}{2}$");
  const classes = new Set(
    [...out.matchAll(/class="([^"]+)"/g)].flatMap((m) => (m[1] as string).split(" ")),
  );
  for (const c of ["sizing", "msupsub", "vlist-t", "mfrac", "reset-size6"]) {
    assert.ok(classes.has(c), `出力に ${c} がない`);
    assert.ok(css.includes(`.${c}`), `CSS に .${c} がない(katex の版が食い違っている)`);
  }
});
