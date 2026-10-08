// Rendering PoC: unified / remark / rehype による Markdown → HTML。
//
// 方針:
//  - 入力は信頼しない。raw HTML は rehype-raw で構文木にしたうえで、rehype-sanitize(GitHub 準拠のスキーマ)に通す。
//  - sanitize より後ろに置く変換(KaTeX・ハイライト・画像 URL の書き換え・アラート)は、自前の変換か、
//    信頼できる出力を作るものに限る。
//  - 外部画像は読み込まない(local first)。ローカル画像だけをホスト経由の URL に書き換える。
//  - Mermaid は DOM が要るので、HTML 文字列化の後に hydrateDiagrams() で描画する(遅延ロード)。

import { unified } from "unified";
import remarkParse from "remark-parse";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import remarkRehype from "remark-rehype";
import rehypeRaw from "rehype-raw";
import rehypeSanitize, { defaultSchema } from "rehype-sanitize";
import rehypeKatex from "rehype-katex";
import rehypeStringify from "rehype-stringify";
import { visit } from "unist-util-visit";
import { toString } from "hast-util-to-string";
import GithubSlugger from "github-slugger";
import { createStarryNight, common } from "@wooorm/starry-night";
import { resolveLink } from "./model.js";

const ALERTS = ["note", "tip", "important", "warning", "caution"];

// GitHub はインライン数式の `$` について、(1) 内側が空白で始まる/終わる、(2) 閉じの `$` の直後が数字、
// のどちらかなら数式として扱わない(例: 「$5 から $10」は通貨)。remark-math にはこの規則がないので揃える。
function remarkMathGithubCompat() {
  return (tree, file) => {
    const src = String(file.value);
    visit(tree, "inlineMath", (node, index, parent) => {
      const { start, end } = node.position;
      const next = src[end.offset] ?? "";
      // node.value は前後の空白が除かれているので、元のソースで判定する
      const inner = src.slice(start.offset + 1, end.offset - 1);
      if (/\d/.test(next) || /^\s|\s$/.test(inner)) {
        parent.children[index] = { type: "text", value: src.slice(start.offset, end.offset) };
      }
    });
  };
}

// GitHub と同じ方式(github-slugger)で見出しに id を付ける。重複には連番が付く。
function rehypeHeadingIds() {
  return (tree) => {
    const slugger = new GithubSlugger();
    visit(tree, "element", (node) => {
      if (/^h[1-6]$/.test(node.tagName)) node.properties = { ...node.properties, id: slugger.slug(toString(node)) };
    });
  };
}

// > [!NOTE] などを GitHub のアラートの構造に変える。
function rehypeAlerts() {
  return (tree) => {
    visit(tree, "element", (node) => {
      if (node.tagName !== "blockquote") return;
      const p = node.children.find((c) => c.type === "element");
      const first = p?.tagName === "p" ? p.children[0] : null;
      const m = first?.type === "text" && /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*\n?/i.exec(first.value);
      if (!m) return;
      const kind = m[1].toLowerCase();
      first.value = first.value.slice(m[0].length);
      node.tagName = "div";
      node.properties = { className: ["markdown-alert", `markdown-alert-${kind}`] };
      node.children.unshift({
        type: "element",
        tagName: "p",
        properties: { className: ["markdown-alert-title"] },
        children: [{ type: "text", value: kind[0].toUpperCase() + kind.slice(1) }],
      });
    });
  };
}

// 画像: 相対パスはホスト経由の URL にし、外部 URL は読み込まずに代替表示にする。
function rehypeImages() {
  return (tree, file) => {
    const { docPath, resolveResource } = file.data;
    visit(tree, "element", (node, index, parent) => {
      if (node.tagName !== "img" || !parent) return;
      const src = String(node.properties?.src ?? "");
      const target = src && resolveLink(docPath, src);
      if (target) {
        node.properties.src = resolveResource(target.path);
      } else {
        parent.children[index] = {
          type: "element",
          tagName: "span",
          properties: { className: ["blocked-image"] },
          children: [{ type: "text", value: `[画像をブロックしました: ${node.properties?.alt || src || "(src なし)"}]` }],
        };
      }
    });
  };
}

// コードブロック: Mermaid は印を付けて後で描画し、それ以外は starry-night(GitHub と同じ文法)で着色する。
function rehypeCodeBlocks(starryNight) {
  return (tree) => {
    visit(tree, "element", (node, _i, parent) => {
      if (node.tagName !== "code" || parent?.tagName !== "pre") return;
      const lang = (node.properties?.className ?? []).map(String).find((c) => c.startsWith("language-"))?.slice(9);
      if (!lang || lang === "math") return;
      if (lang === "mermaid") {
        parent.properties = { ...parent.properties, className: ["mermaid-source"] };
        return;
      }
      const scope = starryNight.flagToScope(lang);
      if (scope) node.children = starryNight.highlight(toString(node), scope).children;
    });
  };
}

const schema = {
  ...defaultSchema,
  attributes: {
    ...defaultSchema.attributes,
    // 数式(remark-math)とコードの言語指定を通す。KaTeX の出力は sanitize の後で作るので許可は不要。
    code: [["className", /^language-./, "math-inline", "math-display"]],
    div: [...(defaultSchema.attributes.div ?? []), ["className", "math", "math-display"]],
    span: [...(defaultSchema.attributes.span ?? []), ["className", "math", "math-inline"]],
  },
};

// starry-night は既定で外部 CDN(esm.sh)から WASM を取得するため、onigUrl で同梱ファイルを指定する(local first)。
export async function createRenderer({ onigUrl } = {}) {
  const starryNight = await createStarryNight(common, onigUrl ? { getOnigurumaUrlFetch: () => onigUrl } : undefined);
  const processor = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkMath)
    .use(remarkMathGithubCompat)
    // 脚注の id は sanitize が接頭辞を付ける。ここでも付けると二重になりリンクが切れる
    .use(remarkRehype, { allowDangerousHtml: true, clobberPrefix: "" })
    .use(rehypeRaw)
    .use(rehypeHeadingIds)
    .use(rehypeSanitize, schema)
    .use(rehypeAlerts)
    .use(rehypeImages)
    .use(rehypeKatex, { throwOnError: false, errorColor: "#cf222e", strict: "ignore", trust: false })
    .use(rehypeCodeBlocks, starryNight)
    .use(rehypeStringify);

  // -> { html, ms }
  return {
    renderMarkdown(text, { docPath, resolveResource }) {
      const t0 = performance.now();
      const file = processor.processSync({ value: text, data: { docPath, resolveResource } });
      return { html: String(file), ms: performance.now() - t0 };
    },
  };
}

// アンカー(ページ内リンク先)の要素を探す。sanitize が id に付ける接頭辞(user-content-)に対応する。
export function findAnchor(root, anchor) {
  return root.querySelector(`#${CSS.escape("user-content-" + anchor)}`) ?? root.querySelector(`#${CSS.escape(anchor)}`);
}

// ---------------------------------------------------------------- Mermaid
let mermaidPromise = null;
let diagramSeq = 0;

function loadMermaid() {
  mermaidPromise ??= import("mermaid").then(({ default: mermaid }) => {
    const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: dark ? "dark" : "default", logLevel: "fatal" });
    return mermaid;
  });
  return mermaidPromise;
}

// 描画に失敗しても文書全体は止めず、その場にエラーとソースを表示する。
export async function hydrateDiagrams(root) {
  const blocks = [...root.querySelectorAll("pre.mermaid-source")];
  if (!blocks.length) return { count: 0, errors: 0, ms: 0 };
  const t0 = performance.now();
  let errors = 0;
  const mermaid = await loadMermaid();
  for (const pre of blocks) {
    const source = pre.textContent;
    const id = `mmd-${++diagramSeq}`;
    const box = document.createElement("div");
    try {
      const { svg } = await mermaid.render(id, source);
      box.className = "mermaid-diagram";
      box.innerHTML = svg;
    } catch (err) {
      errors += 1;
      document.getElementById(`d${id}`)?.remove();
      box.className = "render-error";
      const title = document.createElement("strong");
      title.textContent = "Mermaid の描画に失敗しました";
      const msg = document.createElement("pre");
      msg.textContent = String(err?.message ?? err).split("\n").slice(0, 4).join("\n");
      const src = document.createElement("pre");
      src.textContent = source;
      box.append(title, msg, src);
    }
    pre.replaceWith(box);
  }
  return { count: blocks.length, errors, ms: performance.now() - t0 };
}
