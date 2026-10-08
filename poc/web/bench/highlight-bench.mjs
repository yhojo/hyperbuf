// シンタックスハイライトの比較: starry-night(GitHub と同じ文法) と Shiki(Oniguruma / JS 正規表現エンジン)
// 同じコードを、起動時間・1回あたりの時間・出力サイズで比べる。
import { readFileSync } from "node:fs";
import { createStarryNight, common } from "@wooorm/starry-night";
import { toHtml } from "hast-util-to-html";
import { createHighlighter } from "shiki";
import { createJavaScriptRegexEngine } from "shiki/engine/javascript";

const md = readFileSync("../../sample/rendering/02-code.md", "utf8") + readFileSync("../../sample/rendering/07-large.md", "utf8");
const blocks = [...md.matchAll(/```(\w+)\n([\s\S]*?)```/g)].map((m) => ({ lang: m[1], code: m[2] })).filter((b) => b.lang !== "mermaid");
const langs = ["python", "js", "ts", "swift", "rust", "go", "elisp", "bash", "diff", "json", "yaml", "html", "css"];
const alias = { js: "javascript", ts: "typescript", elisp: "emacs-lisp" };
console.log(`ブロック数 ${blocks.length}、コード ${blocks.reduce((n, b) => n + b.code.length, 0)} 文字`);

const bench = async (name, init, run) => {
  const t0 = performance.now();
  const h = await init();
  const initMs = performance.now() - t0;
  for (const b of blocks.slice(0, 20)) run(h, b); // ウォームアップ
  const t1 = performance.now();
  let bytes = 0;
  for (let r = 0; r < 5; r++) for (const b of blocks) bytes += run(h, b).length;
  const ms = (performance.now() - t1) / 5;
  console.log(`${name.padEnd(26)} 初期化 ${initMs.toFixed(0).padStart(5)}ms | 全ブロック ${ms.toFixed(1).padStart(6)}ms | 出力 ${(bytes / 5 / 1024).toFixed(0)}KB`);
};

await bench("starry-night (common)", () => createStarryNight(common), (sn, b) => {
  const scope = sn.flagToScope(b.lang);
  return scope ? toHtml(sn.highlight(b.code, scope)) : b.code;
});
await bench("shiki (oniguruma)", () => createHighlighter({ themes: ["github-light"], langs: langs.map((l) => alias[l] ?? l) }), (h, b) => {
  const lang = alias[b.lang] ?? b.lang;
  return h.getLoadedLanguages().includes(lang) ? h.codeToHtml(b.code, { lang, theme: "github-light" }) : b.code;
});
await bench("shiki (JS regex engine)", () => createHighlighter({ themes: ["github-light"], langs: langs.map((l) => alias[l] ?? l), engine: createJavaScriptRegexEngine() }), (h, b) => {
  const lang = alias[b.lang] ?? b.lang;
  return h.getLoadedLanguages().includes(lang) ? h.codeToHtml(b.code, { lang, theme: "github-light" }) : b.code;
});
