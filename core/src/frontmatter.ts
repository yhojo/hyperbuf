// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// YAML front matter (the `---` block at the very start of a document) -> a table, the way GitHub shows it.
// The pure part with no DOM dependency.
//
//  - "vertical" layout (default): a mapping becomes a table with one row per key (key | value). A sequence of
//    mappings becomes a table with one row per item and one column per key; a sequence of plain values one row.
//  - "horizontal" layout (GitHub's): a mapping becomes a table with the keys in the header row and the values in
//    one body row; a sequence becomes a table with one row and no header.
//  - Nested mappings / sequences become nested tables in both layouts.
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

/** "vertical": one key per row (key | value). "horizontal": keys in the header row, the way GitHub shows it. */
export type FrontMatterLayout = "vertical" | "horizontal";

type Collection = unknown[] | Record<string, unknown>;
const isCollection = (value: unknown): value is Collection =>
  Array.isArray(value) || isMapping(value);

const tr = (cells: Element[]): Element => element("tr", cells);
const th = (key: string): Element => element("th", [text(key)]);

function td(value: unknown, layout: FrontMatterLayout, depth: number): Element {
  if (isCollection(value)) {
    if (depth >= MAX_DEPTH) return element("td", [text("…")]);
    const nested = table(value, layout, depth + 1);
    return element("td", nested ? [nested] : []);
  }
  return element("td", [text(scalar(value))]);
}

/** A sequence whose items are all mappings: one row per item, one column per key (in order of first appearance). */
function records(items: Record<string, unknown>[], layout: FrontMatterLayout, depth: number) {
  const keys = [...new Set(items.flatMap((item) => Object.keys(item)))];
  if (keys.length === 0) return null;
  return element("table", [
    element("thead", [tr(keys.map(th))]),
    element(
      "tbody",
      items.map((item) => tr(keys.map((k) => td(item[k], layout, depth)))),
    ),
  ]);
}

function table(value: Collection, layout: FrontMatterLayout, depth: number): Element | null {
  const cell = (v: unknown): Element => td(v, layout, depth);
  if (Array.isArray(value)) {
    if (value.length === 0) return null;
    if (layout === "vertical") {
      if (value.every(isMapping)) return records(value, layout, depth);
      // Items with structure get a row each; plain values stay on one line
      if (value.some(isCollection)) {
        return element("table", [
          element(
            "tbody",
            value.map((v) => tr([cell(v)])),
          ),
        ]);
      }
    }
    return element("table", [element("tbody", [tr(value.map(cell))])]);
  }
  const keys = Object.keys(value);
  if (keys.length === 0) return null;
  if (layout === "vertical") {
    return element("table", [
      element(
        "tbody",
        keys.map((k) => tr([th(k), cell(value[k])])),
      ),
    ]);
  }
  return element("table", [
    element("thead", [tr(keys.map(th))]),
    element("tbody", [tr(keys.map((k) => cell(value[k])))]),
  ]);
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
export function renderFrontMatter(
  source: string,
  layout: FrontMatterLayout = "vertical",
): Element[] {
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
  const result = table(data, layout, 0);
  if (!result) return [];
  result.properties = { className: [FRONT_MATTER_CLASS] };
  return [result];
}
