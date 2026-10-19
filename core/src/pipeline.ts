// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Markdown -> HTML (unified / remark / rehype). The pure part with no DOM dependency.
//
// Policy:
//  - Input is untrusted. Raw HTML is turned into a syntax tree by rehype-raw, then passed through rehype-sanitize (a GitHub-compatible schema).
//  - Transforms placed after sanitize (KaTeX, highlighting, image URL rewriting, alerts) are limited to our own transforms
//    or ones that produce trusted output.
//  - External images are not loaded (local first). Only local images are rewritten to URLs via the host.
//  - Mermaid needs the DOM, so ui/diagrams.ts renders it after the HTML is turned into a string.
// History of the verification: docs/history/poc-rendering-results.md

import type { Element, ElementContent, Root as HastRoot } from "hast";
import type { Root as MdastRoot } from "mdast";
import { createStarryNight } from "@wooorm/starry-night";
import type { Grammar } from "@wooorm/starry-night";
import { EAGER, LAZY, fenceFlags } from "./grammars.ts";
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
  /** Path of the document to render (used to resolve relative links and images). */
  docPath: string;
  /** Turns the relative path of a local image into a loadable URL (provided by the host). */
  resolveResource: (path: string) => string;
}

export interface RenderResult {
  html: string;
  /** Time taken to render (milliseconds). */
  ms: number;
}

/** Rendering settings (from config.json). */
export interface RenderSettings {
  /** Turn `\_` in math back into `_` (same as Marked 2 and others; default true). src/math.ts */
  mathUnescapeUnderscore: boolean;
}

export interface Renderer {
  /** Changes the settings (call before the first render). */
  configure(settings: Partial<RenderSettings>): void;
  /** Loads the large grammars (Emacs Lisp, etc.) that the body's code blocks use, before rendering. */
  prepare(text: string): Promise<void>;
  renderMarkdown(text: string, context: RenderContext): RenderResult;
}

/**
 * For inline math `$`, GitHub does not treat it as math if either (1) the inside starts/ends with whitespace, or (2) the digit follows the closing `$`
 * (for example, "$5 to $10" is currency). remark-math lacks this rule, so we match it.
 */
const remarkMathGithubCompat: Plugin<[], MdastRoot> = () => (tree, file) => {
  const src = String(file.value);
  visit(tree, "inlineMath", (node, index, parent) => {
    const start = node.position?.start.offset;
    const end = node.position?.end.offset;
    if (start === undefined || end === undefined || index === undefined || !parent) return;
    // node.value has surrounding whitespace removed, so judge from the original source
    const inner = src.slice(start + 1, end - 1);
    if (/\d/.test(src[end] ?? "") || /^\s|\s$/.test(inner)) {
      parent.children[index] = { type: "text", value: src.slice(start, end) };
    }
  });
};

/**
 * Turns `\_` in math back into `_` (makes `$f\_{2}$` a subscript). Compatibility with Marked 2 and others.
 * mdast math / inlineMath keep the content for rendering (hast, `data.hChildren`) separately, so fix both.
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

/**
 * An expression written on one line as `$$ … $$` (no newlines around it) becomes inline math in remark-math and is rendered left-packed.
 * An expression enclosed in `$$` is rendered as block math (centered), as the writer intended (same as Marked 2).
 */
const remarkMathDoubleDollar: Plugin<[], MdastRoot> = () => (tree, file) => {
  const src = String(file.value);
  visit(tree, "inlineMath", (node) => {
    const start = node.position?.start.offset;
    if (start === undefined || !src.startsWith("$$", start)) return;
    const data = (node.data ??= {});
    data.hProperties = { ...data.hProperties, className: ["language-math", "math-display"] };
  });
};

/** Gives headings ids the GitHub way (github-slugger). Duplicates get a sequence number. */
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
 * Keeps the original Markdown position on block elements.
 *  - data-source-line: start line (for "open at line N")
 *  - data-source-start / data-source-end: start and end character offsets (UTF-16). Maps the selected range in the viewer
 *    to the original position, to pass the edit position to the editor (docs/dev/edit-location.md §4)
 *  - data-source-end-line: end line
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

/** Turns > [!NOTE] and the like into GitHub's alert structure. */
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

/** Images: relative paths become URLs via the host; external URLs are not loaded and get a placeholder instead. */
const rehypeImages: Plugin<[], HastRoot> = () => (tree, file: VFile) => {
  const { docPath, resolveResource } = file.data;
  if (docPath === undefined || resolveResource === undefined) {
    throw new Error("rehypeImages: docPath and resolveResource are required");
  }
  visit(tree, "element", (node, index, parent) => {
    if (node.tagName !== "img" || !parent || index === undefined) return;
    const src = String(node.properties?.["src"] ?? "");
    const target = src ? resolveLink(docPath, src) : null;
    if (target) {
      node.properties["src"] = resolveResource(target.path);
    } else {
      const label = String(node.properties?.["alt"] || src || "(no src)");
      const replacement: Element = {
        type: "element",
        tagName: "span",
        properties: { className: ["blocked-image"] },
        children: [{ type: "text", value: `[Image blocked: ${label}]` }],
      };
      parent.children[index] = replacement as ElementContent;
    }
  });
};

/** Code blocks: Mermaid is marked and rendered later; everything else is colored with starry-night (the same grammars as GitHub). */
const rehypeCodeBlocks: Plugin<[() => StarryNight], HastRoot> = (current) => (tree) => {
  const starryNight = current();
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
    if (!scope) return;
    try {
      node.children = starryNight.highlight(toString(node), scope).children as ElementContent[];
    } catch {
      // The grammar is not loaded yet (a path that bypasses prepare). Show it as is, without coloring
    }
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
    // Let math (remark-math) and code language info through. KaTeX output is made after sanitize, so no allowance is needed.
    code: [["className", /^language-./, "math-inline", "math-display"]],
    div: [...(attributes["div"] ?? []), ["className", "math", "math-display"]],
    span: [...(attributes["span"] ?? []), ["className", "math", "math-inline"]],
  },
};
type SchemaWithAttributes = SchemaWithAttributesBase;
type SchemaWithAttributesBase = NonNullable<SanitizeSchema>;

/**
 * starry-night fetches WASM from an external CDN (esm.sh) by default, so specify the bundled file with onigUrl (local first).
 */
export async function createRenderer(options: { onigUrl?: URL } = {}): Promise<Renderer> {
  const { onigUrl } = options;
  const starryOptions = onigUrl ? { getOnigurumaUrlFetch: () => onigUrl } : undefined;
  let starryNight = await createStarryNight(EAGER, starryOptions);
  // Add large grammars when they become necessary. starry-night's register() re-fetches the WASM from an external CDN, so do not use it;
  // instead create a new starry-night that points at the bundled WASM and swap it in (local first)
  const requested = new Set<string>();
  const active: Grammar[] = [];
  let chain: Promise<void> = Promise.resolve();
  const settings: RenderSettings = { mathUnescapeUnderscore: true };
  const processor = unified()
    .use(remarkParse)
    .use(remarkGfm)
    .use(remarkMath)
    .use(remarkMathGithubCompat)
    .use(remarkMathDoubleDollar)
    .use(remarkMathUnescape(settings))
    // Footnote ids get a prefix from sanitize. Adding it here too would double it and break the links
    .use(remarkRehype, { allowDangerousHtml: true, clobberPrefix: "" })
    .use(rehypeRaw)
    .use(rehypeHeadingIds)
    .use(rehypeSourceLines)
    .use(rehypeSanitize, schema)
    .use(rehypeAlerts)
    .use(rehypeImages)
    // An invalid expression makes rehype-katex show an error (errorColor) in place without stopping the whole document
    .use(rehypeKatex, { errorColor: "#cf222e", strict: "ignore", trust: false })
    .use(rehypeCodeBlocks, () => starryNight)
    .use(rehypeStringify);

  return {
    configure(next) {
      Object.assign(settings, next);
    },
    async prepare(text) {
      const flags = fenceFlags(text);
      const needed = LAZY.filter(
        (g) => !requested.has(g.scope) && g.flags.some((f) => flags.has(f)),
      );
      for (const g of needed) requested.add(g.scope);
      if (needed.length > 0) {
        chain = chain.then(async () => {
          try {
            active.push(...(await Promise.all(needed.map((g) => g.load()))));
            starryNight = await createStarryNight([...EAGER, ...active], starryOptions);
          } catch {
            for (const g of needed) requested.delete(g.scope);
          }
        });
      }
      await chain; // if a grammar is loading, wait until it finishes (so everything is ready before rendering)
    },
    renderMarkdown(text, { docPath, resolveResource }) {
      const t0 = performance.now();
      const file = processor.processSync({ value: text, data: { docPath, resolveResource } });
      return { html: String(file), ms: performance.now() - t0 };
    },
  };
}
