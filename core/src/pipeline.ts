// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Markdown → HTML(unified / remark / rehype)。DOM に依存しない純粋な部分。
//
// 方針:
//  - 入力は信頼しない。raw HTML は rehype-raw で構文木にしたうえで、rehype-sanitize(GitHub 準拠のスキーマ)に通す。
//  - sanitize より後ろに置く変換(KaTeX・ハイライト・画像 URL の書き換え・アラート)は、自前の変換か、
//    信頼できる出力を作るものに限る。
//  - 外部画像は読み込まない(local first)。ローカル画像だけをホスト経由の URL に書き換える。
//  - Mermaid は DOM が要るので、HTML 文字列化の後に、ui/diagrams.ts が描画する。
// 検証の経緯: docs/poc-rendering-results.md

import type { Element, ElementContent, Root as HastRoot } from "hast";
import type { Root as MdastRoot } from "mdast";
import { createStarryNight, common } from "@wooorm/starry-night";
import GithubSlugger from "github-slugger";
import { toString } from "hast-util-to-string";
import rehypeKatex from "rehype-katex";
import rehypeRaw from "rehype-raw";
import rehypeSanitize, { defaultSchema } from "rehype-sanitize";
import type { Options as SanitizeSchema } from "rehype-sanitize";
import rehypeStringify from "rehype-stringify";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import remarkParse from "remark-parse";
import remarkRehype from "remark-rehype";
import { unified } from "unified";
import type { Plugin } from "unified";
import { visit } from "unist-util-visit";
import type { VFile } from "vfile";
import { unescapeMathUnderscores } from "./math.ts";
import { resolveLink } from "./model.ts";

declare module "vfile" {
  interface DataMap {
    docPath: string;
    resolveResource: (path: string) => string;
  }
}

export interface RenderContext {
  /** 描画する文書のパス(相対リンク・画像の解決に使う)。 */
  docPath: string;
  /** ローカル画像の相対パスを、読み込める URL にする(ホストが提供する)。 */
  resolveResource: (path: string) => string;
}

export interface RenderResult {
  html: string;
  /** 描画にかかった時間(ミリ秒)。 */
  ms: number;
}

/** 描画の設定(config.json 由来)。 */
export interface RenderSettings {
  /** 数式の中の `\_` を `_` に戻す(Marked 2 などと同じ。既定は true)。src/math.ts */
  mathUnescapeUnderscore: boolean;
}

export interface Renderer {
  /** 設定を変える(最初の描画の前に呼ぶ)。 */
  configure(settings: Partial<RenderSettings>): void;
  renderMarkdown(text: string, context: RenderContext): RenderResult;
}

/**
 * GitHub はインライン数式の `$` について、(1) 内側が空白で始まる/終わる、(2) 閉じの `$` の直後が数字、
 * のどちらかなら数式として扱わない(例: 「$5 から $10」は通貨)。remark-math にはこの規則がないので揃える。
 */
const remarkMathGithubCompat: Plugin<[], MdastRoot> = () => (tree, file) => {
  const src = String(file.value);
  visit(tree, "inlineMath", (node, index, parent) => {
    const start = node.position?.start.offset;
    const end = node.position?.end.offset;
    if (start === undefined || end === undefined || index === undefined || !parent) return;
    // node.value は前後の空白が除かれているので、元のソースで判定する
    const inner = src.slice(start + 1, end - 1);
    if (/\d/.test(src[end] ?? "") || /^\s|\s$/.test(inner)) {
      parent.children[index] = { type: "text", value: src.slice(start, end) };
    }
  });
};

/**
 * 数式の中の `\_` を `_` に戻す(`$f\_{2}$` を、下付き文字にする)。Marked 2 などとの互換。
 * mdast の math / inlineMath は、描画用の hast の中身(`data.hChildren`)を別に持つので、両方を直す。
 */
const remarkMathUnescape =
  (settings: RenderSettings): Plugin<[], MdastRoot> =>
  () =>
  (tree) => {
    if (!settings.mathUnescapeUnderscore) return;
    const fix = (node: { value: string; data?: Record<string, unknown> }): void => {
      node.value = unescapeMathUnderscores(node.value);
      const children = node.data?.["hChildren"];
      if (Array.isArray(children)) {
        for (const child of children as { type: string; value?: string }[]) {
          if (child.type === "text" && typeof child.value === "string") {
            child.value = unescapeMathUnderscores(child.value);
          }
        }
      }
    };
    visit(tree, (node) => {
      if (node.type === "math" || node.type === "inlineMath") {
        fix(node as unknown as { value: string; data?: Record<string, unknown> });
      }
    });
  };

/** GitHub と同じ方式(github-slugger)で見出しに id を付ける。重複には連番が付く。 */
const rehypeHeadingIds: Plugin<[], HastRoot> = () => (tree) => {
  const slugger = new GithubSlugger();
  visit(tree, "element", (node) => {
    if (/^h[1-6]$/.test(node.tagName)) {
      node.properties = { ...node.properties, id: slugger.slug(toString(node)) };
    }
  });
};

const LINE_TAGS = new Set([
  "p",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "li",
  "pre",
  "table",
  "blockquote",
  "ul",
  "ol",
  "hr",
  "details",
]);

/**
 * 元の Markdown の位置を、ブロック要素に残す。
 *  - data-source-line: 開始行(「N 行目を開く」用)
 *  - data-source-start / data-source-end: 開始・終了の文字オフセット(UTF-16)。ビューアから、編集位置を
 *    エディタへ渡すために、選択した範囲を、元の位置に対応づける(docs/integration-protocol.md §10)
 *  - data-source-end-line: 終了行
 */
const rehypeSourceLines: Plugin<[], HastRoot> = () => (tree) => {
  visit(tree, "element", (node) => {
    const { position } = node;
    if (!LINE_TAGS.has(node.tagName) || !position) return;
    const properties: Record<string, string> = { dataSourceLine: String(position.start.line) };
    if (position.start.offset !== undefined && position.end.offset !== undefined) {
      properties["dataSourceStart"] = String(position.start.offset);
      properties["dataSourceEnd"] = String(position.end.offset);
      properties["dataSourceEndLine"] = String(position.end.line);
    }
    node.properties = { ...node.properties, ...properties };
  });
};

/** > [!NOTE] などを、GitHub のアラートの構造に変える。 */
const rehypeAlerts: Plugin<[], HastRoot> = () => (tree) => {
  visit(tree, "element", (node) => {
    if (node.tagName !== "blockquote") return;
    const p = node.children.find((c): c is Element => c.type === "element");
    const first = p?.tagName === "p" ? p.children[0] : undefined;
    if (first?.type !== "text") return;
    const m = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*\n?/i.exec(first.value);
    if (!m) return;
    const kind = (m[1] ?? "note").toLowerCase();
    first.value = first.value.slice(m[0].length);
    node.tagName = "div";
    node.properties = { className: ["markdown-alert", `markdown-alert-${kind}`] };
    node.children.unshift({
      type: "element",
      tagName: "p",
      properties: { className: ["markdown-alert-title"] },
      children: [{ type: "text", value: kind.charAt(0).toUpperCase() + kind.slice(1) }],
    });
  });
};

/** 画像: 相対パスはホスト経由の URL にし、外部 URL は読み込まずに代替表示にする。 */
const rehypeImages: Plugin<[], HastRoot> = () => (tree, file: VFile) => {
  const { docPath, resolveResource } = file.data;
  if (docPath === undefined || resolveResource === undefined) {
    throw new Error("rehypeImages: docPath と resolveResource が必要です");
  }
  visit(tree, "element", (node, index, parent) => {
    if (node.tagName !== "img" || !parent || index === undefined) return;
    const src = String(node.properties?.["src"] ?? "");
    const target = src ? resolveLink(docPath, src) : null;
    if (target) {
      node.properties["src"] = resolveResource(target.path);
    } else {
      const label = String(node.properties?.["alt"] || src || "(src なし)");
      const replacement: Element = {
        type: "element",
        tagName: "span",
        properties: { className: ["blocked-image"] },
        children: [{ type: "text", value: `[画像をブロックしました: ${label}]` }],
      };
      parent.children[index] = replacement as ElementContent;
    }
  });
};

/** コードブロック: Mermaid は印を付けて後で描画し、それ以外は starry-night(GitHub と同じ文法)で着色する。 */
const rehypeCodeBlocks: Plugin<[StarryNight], HastRoot> = (starryNight) => (tree) => {
  visit(tree, "element", (node, _index, parent) => {
    if (
      node.tagName !== "code" ||
      !parent ||
      parent.type !== "element" ||
      parent.tagName !== "pre"
    ) {
      return;
    }
    const classNames = Array.isArray(node.properties?.["className"])
      ? node.properties["className"]
      : [];
    const lang = classNames
      .map(String)
      .find((c) => c.startsWith("language-"))
      ?.slice("language-".length);
    if (!lang || lang === "math") return;
    if (lang === "mermaid") {
      parent.properties = { ...parent.properties, className: ["mermaid-source"] };
      return;
    }
    const scope = starryNight.flagToScope(lang);
    if (scope)
      node.children = starryNight.highlight(toString(node), scope).children as ElementContent[];
  });
};

type StarryNight = Awaited<ReturnType<typeof createStarryNight>>;

const attributes = defaultSchema.attributes ?? {};
const schema: SchemaWithAttributes = {
  ...defaultSchema,
  attributes: {
    ...attributes,
    "*": [
      ...(attributes["*"] ?? []),
      "dataSourceLine",
      "dataSourceEndLine",
      "dataSourceStart",
      "dataSourceEnd",
    ],
    // 数式(remark-math)とコードの言語指定を通す。KaTeX の出力は sanitize の後で作るので許可は不要。
    code: [["className", /^language-./, "math-inline", "math-display"]],
    div: [...(attributes["div"] ?? []), ["className", "math", "math-display"]],
    span: [...(attributes["span"] ?? []), ["className", "math", "math-inline"]],
  },
};
type SchemaWithAttributes = SchemaWithAttributesBase;
type SchemaWithAttributesBase = NonNullable<SanitizeSchema>;

/**
 * starry-night は既定で外部 CDN(esm.sh)から WASM を取得するため、onigUrl で同梱ファイルを指定する(local first)。
 */
export async function createRenderer(options: { onigUrl?: URL } = {}): Promise<Renderer> {
  const { onigUrl } = options;
  const starryNight = await createStarryNight(
    common,
    onigUrl ? { getOnigurumaUrlFetch: () => onigUrl } : undefined,
  );
  const settings: RenderSettings = { mathUnescapeUnderscore: true };
  const processor = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkMath)
    .use(remarkMathGithubCompat)
    .use(remarkMathUnescape(settings))
    // 脚注の id は sanitize が接頭辞を付ける。ここでも付けると二重になりリンクが切れる
    .use(remarkRehype, { allowDangerousHtml: true, clobberPrefix: "" })
    .use(rehypeRaw)
    .use(rehypeHeadingIds)
    .use(rehypeSourceLines)
    .use(rehypeSanitize, schema)
    .use(rehypeAlerts)
    .use(rehypeImages)
    // 不正な式は、rehype-katex が文書全体を止めずに、その場にエラー(errorColor)を表示する
    .use(rehypeKatex, { errorColor: "#cf222e", strict: "ignore", trust: false })
    .use(rehypeCodeBlocks, starryNight)
    .use(rehypeStringify);

  return {
    configure(next) {
      Object.assign(settings, next);
    },
    renderMarkdown(text, { docPath, resolveResource }) {
      const t0 = performance.now();
      const file = processor.processSync({ value: text, data: { docPath, resolveResource } });
      return { html: String(file), ms: performance.now() - t0 };
    },
  };
}
