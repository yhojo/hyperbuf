// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// YAML front matter (the `---` block at the very start of a document) -> a table, the way GitHub shows it.
// The pure part with no DOM dependency.
//
//  - A mapping becomes a table with the keys in the header row and the values in one body row.
//  - A sequence becomes a table with one row and no header. Nested mappings / sequences become nested tables.
//  - YAML that cannot be parsed is shown in place as its source with the error, without breaking the document.
//
// The input is untrusted like the rest of the document: values only ever become text nodes, and the result
// still passes through rehype-sanitize (pipeline.ts).

import type { Element, ElementContent } from "hast";
import { parse } from "yaml";

/** Class of the outermost table (allowed by the sanitize schema in pipeline.ts; styled in ui/style.css). */
export const FRONT_MATTER_CLASS = "front-matter";
/** Class of the message shown above the source when the YAML is invalid. */
export const FRONT_MATTER_ERROR_CLASS = "front-matter-error";

/** Nesting deeper than this is not expanded (untrusted input; keeps the DOM bounded). */
const MAX_DEPTH = 8;

const element = (tagName: string, children: ElementContent[], className?: string): Element => ({
  type: "element",
  tagName,
  properties: className ? { className: [className] } : {},
  children,
});

const text = (value: string): ElementContent => ({ type: "text", value });

const isMapping = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function scalar(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "object") return JSON.stringify(value) ?? "";
  return String(value);
}

function cell(tagName: "td", value: unknown, depth: number): Element {
  if (Array.isArray(value) || isMapping(value)) {
    if (depth >= MAX_DEPTH) return element(tagName, [text("…")]);
    const nested = table(value, depth + 1);
    return element(tagName, nested ? [nested] : []);
  }
  return element(tagName, [text(scalar(value))]);
}

function table(value: unknown[] | Record<string, unknown>, depth: number): Element | null {
  const row = (values: unknown[]): Element =>
    element("tbody", [
      element(
        "tr",
        values.map((v) => cell("td", v, depth)),
      ),
    ]);
  if (Array.isArray(value)) {
    return value.length > 0 ? element("table", [row(value)]) : null;
  }
  const keys = Object.keys(value);
  if (keys.length === 0) return null;
  const head = element("thead", [
    element(
      "tr",
      keys.map((k) => element("th", [text(k)])),
    ),
  ]);
  return element("table", [head, row(keys.map((k) => value[k]))]);
}

function errorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  // The yaml package appends a source excerpt after the first line; the source is shown below anyway.
  // Its line numbers count from the first line of the YAML, which is line 2 of the document (after `---`)
  return (message.split("\n")[0] ?? "")
    .trim()
    .replace(/:$/, "")
    .replace(/ at line (\d+),/, (_, line: string) => ` at line ${Number(line) + 1},`);
}

/** The source as a YAML code block (highlighted later by rehypeCodeBlocks), with a message above it. */
function fallback(source: string, message: string): Element[] {
  return [
    element("p", [text(`Front matter: ${message}`)], FRONT_MATTER_ERROR_CLASS),
    element("pre", [element("code", [text(source + "\n")], "language-yaml")]),
  ];
}

/**
 * Renders the content of a front matter block (without the `---` fences).
 * Returns no element when there is nothing to show (empty block, empty mapping).
 */
export function renderFrontMatter(source: string): Element[] {
  let data: unknown;
  try {
    data = parse(source);
  } catch (error) {
    return fallback(source, errorMessage(error));
  }
  if (data === null || data === undefined) return [];
  if (!Array.isArray(data) && !isMapping(data)) {
    return fallback(source, "expected a mapping or a sequence");
  }
  const result = table(data, 0);
  if (!result) return [];
  result.properties = { className: [FRONT_MATTER_CLASS] };
  return [result];
}
