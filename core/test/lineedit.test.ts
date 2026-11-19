// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import assert from "node:assert/strict";
import test from "node:test";
import { clipboardLine, createLineEditor, isLineEditKey } from "../src/lineedit.ts";
import type { Line, LineEditor } from "../src/lineedit.ts";

/** "ab|cd" -> cursor after b; "a[bc]d" -> selection bc; "a]bc[d" -> the same selection made backward. */
function line(spec: string): Line {
  const cursor = spec.indexOf("|");
  if (cursor >= 0) return { text: spec.replace("|", ""), start: cursor, end: cursor };
  const backward = spec.indexOf("]") < spec.indexOf("[");
  const text = spec.replace(/[[\]]/g, "");
  const marks = [spec.indexOf("["), spec.indexOf("]")].sort((a, b) => a - b);
  const start = marks[0] ?? 0;
  const end = (marks[1] ?? 1) - 1;
  return backward ? { text, start, end, backward } : { text, start, end };
}

function show(l: Line): string {
  if (l.start === l.end) return `${l.text.slice(0, l.start)}|${l.text.slice(l.start)}`;
  return `${l.text.slice(0, l.start)}[${l.text.slice(l.start, l.end)}]${l.text.slice(l.end)}`;
}

/** Applies keys in order and returns the resulting line. */
function run(editor: LineEditor, spec: string, ...keys: string[]): string {
  let current = line(spec);
  for (const key of keys) {
    const edit = editor.key(key, current);
    assert.ok(edit, `${key} is a line-editing key`);
    current = edit.line;
  }
  return show(current);
}

const one = (spec: string, ...keys: string[]): string => run(createLineEditor(), spec, ...keys);

test("keys that are not line-editing keys are left to the caller", () => {
  const editor = createLineEditor();
  for (const name of [
    "RET",
    "C-g",
    "C-n",
    "C-p",
    "M-p",
    "M-n",
    "TAB",
    "a",
    "C-s",
    "C-/",
    "C-SPC",
  ]) {
    assert.equal(isLineEditKey(name), false, name);
    assert.equal(editor.key(name, line("ab|")), null, name);
  }
  assert.equal(isLineEditKey("M-DEL"), true);
});

test("character and line movement", () => {
  assert.equal(one("ab|cd", "C-a"), "|abcd");
  assert.equal(one("ab|cd", "C-e"), "abcd|");
  assert.equal(one("ab|cd", "C-f"), "abc|d");
  assert.equal(one("ab|cd", "C-b"), "a|bcd");
  assert.equal(one("abcd|", "C-f"), "abcd|");
  assert.equal(one("|abcd", "C-b"), "|abcd");
});

test("character movement does not split a surrogate pair or a combined character", () => {
  assert.equal(one("|😀a", "C-f"), "😀|a");
  assert.equal(one("😀|a", "C-b"), "|😀a");
  assert.equal(one("|がa", "C-f"), "が|a");
  assert.equal(one("|😀a", "C-d"), "|a");
});

test("movement starts from point: the end of a selection, or its start when made backward", () => {
  assert.equal(one("a[bc]de", "C-f"), "abcd|e");
  assert.equal(one("a]bc[de", "C-f"), "ab|cde");
  assert.equal(one("a]bc[de", "C-b"), "|abcde");
});

test("word movement: words are runs of letters and digits", () => {
  assert.equal(one("|foo bar", "M-f"), "foo| bar");
  assert.equal(one("foo| bar", "M-f"), "foo bar|");
  assert.equal(one("foo bar|", "M-b"), "foo |bar");
  assert.equal(one("foo |bar", "M-b"), "|foo bar");
  assert.equal(one("~/docs/read-me.md|", "M-b"), "~/docs/read-me.|md");
  assert.equal(one("~/docs/read-me.md|", "M-b", "M-b", "M-b"), "~/docs/|read-me.md");
  assert.equal(one("|設計 メモ2", "M-f", "M-f"), "設計 メモ2|");
});

test("C-d deletes the next character (or the selection) without killing", () => {
  const editor = createLineEditor();
  assert.equal(run(editor, "a|bc", "C-d"), "a|c");
  assert.equal(run(editor, "a[bc]d", "C-d"), "a|d");
  assert.equal(run(editor, "abc|", "C-d"), "abc|");
  assert.equal(run(editor, "x|", "C-y"), "x|", "nothing was killed");
});

test("kills remove text and can be yanked back", () => {
  assert.equal(one("foo |bar baz", "C-k"), "foo |");
  assert.equal(one("foo |bar baz", "C-k", "C-a", "C-y"), "bar baz|foo ");
  assert.equal(one("foo bar| baz", "C-u"), "| baz");
  assert.equal(one("foo |bar baz", "M-d"), "foo | baz");
  assert.equal(one("~/docs/notes|", "M-DEL"), "~/docs/|");
  assert.equal(one("~/docs/|", "M-DEL"), "~/|");
  assert.equal(one("a[bc]d", "C-w"), "a|d");
  assert.equal(one("a[bc]d", "C-w", "C-e", "C-y"), "adbc|");
});

test("a kill reports the text to copy to the clipboard", () => {
  const editor = createLineEditor();
  assert.equal(editor.key("C-k", line("ab|cd"))?.copy, "cd");
  assert.equal(editor.key("M-w", line("a[bc]d"))?.copy, "bc");
  assert.equal(editor.key("C-k", line("abcd|"))?.copy, undefined, "nothing to kill");
  assert.equal(editor.key("C-w", line("ab|cd"))?.copy, undefined, "no selection");
  assert.equal(editor.key("C-a", line("ab|cd"))?.copy, undefined);
});

test("consecutive kills join into one entry in text order", () => {
  const forward = createLineEditor();
  assert.equal(run(forward, "|one two three", "M-d", "M-d"), "| three");
  assert.equal(run(forward, "|", "C-y"), "one two|");

  const backward = createLineEditor();
  assert.equal(run(backward, "a/b/c|", "M-DEL", "M-DEL"), "a/|");
  assert.equal(run(backward, "|", "C-y"), "b/c|");

  const copy = createLineEditor();
  copy.key("M-d", line("|one two"));
  assert.equal(
    copy.key("M-d", line("| two"))?.copy,
    "one two",
    "the clipboard gets the joined text",
  );
});

test("a kill after something else starts a new entry", () => {
  const editor = createLineEditor();
  run(editor, "|one two", "M-d");
  editor.reset(); // typing, clicking, …
  run(editor, "| two", "M-d");
  assert.equal(run(editor, "|", "C-y"), " two|");
  assert.equal(run(editor, "|", "C-y", "M-y"), "one|");

  const moved = createLineEditor();
  assert.equal(run(moved, "|one two", "M-d", "C-e", "M-DEL", "C-y"), " two|");
});

test("M-w copies the selection without changing the line", () => {
  const editor = createLineEditor();
  assert.equal(run(editor, "a[bc]d", "M-w"), "a[bc]d");
  assert.equal(run(editor, "x|", "C-y"), "xbc|");
});

test("C-y replaces the selection", () => {
  const editor = createLineEditor();
  run(editor, "[new]", "M-w");
  assert.equal(run(editor, "a[old]b", "C-y"), "anew|b");
});

test("M-y walks the kill ring, only right after a yank", () => {
  const editor = createLineEditor();
  for (const word of ["one", "two", "three"]) run(editor, `[${word}]`, "M-w");
  assert.equal(run(editor, "<|>", "C-y"), "<three|>");
  assert.equal(run(editor, "<|>", "C-y", "M-y"), "<two|>");
  assert.equal(
    run(editor, "<|>", "C-y", "M-y", "M-y"),
    "<three|>",
    "C-y continues from the entry M-y chose",
  );
  assert.equal(run(editor, "<|>", "C-y", "M-y", "M-y", "M-y"), "<three|>", "wraps around");

  editor.reset();
  assert.equal(run(editor, "<two|>", "M-y"), "<two|>", "not after typing");
  assert.equal(run(createLineEditor(), "<|>", "M-y"), "<|>", "empty ring");
});

test("a new kill makes C-y yank the newest entry again", () => {
  const editor = createLineEditor();
  run(editor, "[one]", "M-w");
  run(editor, "[two]", "M-w");
  assert.equal(run(editor, "|", "C-y", "M-y"), "one|");
  run(editor, "[three]", "M-w");
  assert.equal(run(editor, "|", "C-y"), "three|");
});

test("C-y takes the clipboard into the ring when another app changed it", () => {
  const editor = createLineEditor();
  run(editor, "[mine]", "M-w");
  assert.equal(
    show(editor.key("C-y", line("|"), "mine")!.line),
    "mine|",
    "same as the newest kill",
  );
  assert.equal(show(editor.key("C-y", line("|"), "theirs")!.line), "theirs|");
  // The clipboard text became a kill-ring entry: M-y reaches the previous kill
  const popped = editor.key("M-y", line("theirs|"), null);
  assert.equal(show(popped!.line), "mine|");
  assert.equal(
    show(editor.key("C-y", line("|"), null)!.line),
    "mine|",
    "no clipboard: the ring only",
  );
});

test("an unchanged clipboard does not undo the entry M-y chose", () => {
  const editor = createLineEditor();
  run(editor, "[one]", "M-w");
  run(editor, "[two]", "M-w");
  const yank = (spec: string): string => show(editor.key("C-y", line(spec), "two")!.line);
  assert.equal(yank("|"), "two|");
  assert.equal(run(editor, "two|", "M-y"), "one|");
  assert.equal(yank("|"), "one|", "the clipboard still holds our own kill");
});

test("only the first non-empty line of the clipboard is used", () => {
  assert.equal(clipboardLine("a/b.md\nsecond"), "a/b.md");
  assert.equal(clipboardLine("\r\n\r\nfirst\r\nsecond"), "first");
  assert.equal(clipboardLine("\n\n"), "");
  assert.equal(clipboardLine(null), "");
  assert.equal(show(createLineEditor().key("C-y", line("|"), "one\ntwo")!.line), "one|");
});

test("the kill ring keeps a limited number of entries", () => {
  const editor = createLineEditor(2);
  for (const word of ["one", "two", "three"]) run(editor, `[${word}]`, "M-w");
  assert.equal(run(editor, "|", "C-y", "M-y", "M-y"), "three|");
});
