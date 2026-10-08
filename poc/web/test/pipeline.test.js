import test from "node:test";
import assert from "node:assert/strict";
import { createRenderer } from "../pipeline.js";

const renderer = await createRenderer();

const ctx = { docPath: "docs/a.md", resolveResource: (p) => `res://${p}` };
const html = (md) => renderer.renderMarkdown(md, ctx).html;

test("sanitize: script・イベントハンドラ・javascript: URL を除去する", () => {
  const out = html(
    [
      '<script>alert(1)</script>',
      '<img src="x.png" onerror="alert(1)">',
      '<a href="javascript:alert(1)">x</a>',
      '<iframe src="https://example.com"></iframe>',
      '<div onclick="alert(1)" style="position:fixed">d</div>',
      '[md](javascript:alert(1))',
    ].join("\n\n"),
  );
  assert.doesNotMatch(out, /<script|onerror|onclick|javascript:|<iframe|style=/i);
});

test("GFM: 表・タスクリスト・取り消し線・自動リンク・脚注", () => {
  const out = html("| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n\n~~del~~ https://example.com\n\nfoot[^1]\n\n[^1]: note\n");
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
  assert.match(out, /src="res:\/\/docs\/img\/x\.svg"/);
  assert.match(out, /src="res:\/\/up\.png"/);
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
