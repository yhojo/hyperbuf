import assert from "node:assert/strict";
import test from "node:test";
import {
  CONTEXT_LENGTH,
  EXPECT_LIMIT,
  lineStarts,
  locateInSource,
  offsetToPosition,
  uniqueMatch,
} from "../src/locate.ts";

/** 段落のブロックの位置(UTF-16 のオフセット)。テストでは、空行で区切られた段落を、ブロックとみなす。 */
function paragraphs(text: string): { start: number; end: number }[] {
  const out: { start: number; end: number }[] = [];
  let offset = 0;
  for (const chunk of text.split(/\n\n/)) {
    out.push({ start: offset, end: offset + chunk.length });
    offset += chunk.length + 2;
  }
  return out;
}

const locate = (text: string, block: number, selection: string) => {
  const b = paragraphs(text)[block];
  assert.ok(b);
  return locateInSource({
    path: "a.md",
    text,
    version: 1,
    blockStart: b.start,
    blockEnd: b.end,
    selection,
  });
};

test("行の開始オフセット(LF・CRLF・CR)", () => {
  assert.deepEqual(lineStarts("a\nb\nc"), [0, 2, 4]);
  assert.deepEqual(lineStarts("a\r\nb\r\nc"), [0, 3, 6]);
  assert.deepEqual(lineStarts("a\rb"), [0, 2]);
  assert.deepEqual(lineStarts(""), [0]);
});

test("桁は、コードポイントで数える(サロゲートペアは 1 文字)", () => {
  const text = "😀a日本\nxyz";
  const starts = lineStarts(text);
  // 「😀」は UTF-16 で 2 単位。「a」の位置は、UTF-16 では 2、コードポイントでは 1
  assert.deepEqual(offsetToPosition(starts, text, 2), { line: 1, column: 2 });
  assert.deepEqual(offsetToPosition(starts, text, 3), { line: 1, column: 3 });
  assert.deepEqual(offsetToPosition(starts, text, text.indexOf("xyz") + 1), { line: 2, column: 2 });
});

test("選択が、ブロックの中にちょうど 1 か所なら、exact", () => {
  const text = "# 見出し\n\nこの文には、独自の語があります。\n\n別の段落です。";
  const loc = locate(text, 1, "独自の語");
  assert.equal(loc.precision, "exact");
  assert.equal(loc.expect, "独自の語");
  // 「この文には、」は 6 文字なので、「独自の語」は 7 桁目から(終了は、含まない位置)
  assert.deepEqual(loc.range.start, { line: 3, column: 7 });
  assert.deepEqual(loc.range.end, { line: 3, column: 11 });
  // 文脈は、行(ブロック)をまたいでよい。Emacs は「直前の文字列が、この文脈で終わるか」で照合する
  assert.equal(loc.context.before, "# 見出し\n\nこの文には、");
  assert.equal(loc.context.after, "があります。\n\n別の段落です。");
  assert.equal(loc.selection, "独自の語");
});

test("同じ文言が、同じブロックに複数あれば、block(推測しない)", () => {
  const text = "foo と bar と foo と baz";
  const loc = locate(text, 0, "foo");
  assert.equal(loc.precision, "block");
  assert.equal(loc.expect, text);
  assert.deepEqual(loc.range.start, { line: 1, column: 1 });
});

test("同じ文言が、別のブロックにあっても、指したブロックの中で 1 か所なら exact", () => {
  const text = "foo はここ\n\nfoo はここにも";
  const loc = locate(text, 1, "foo");
  assert.equal(loc.precision, "exact");
  assert.deepEqual(loc.range.start, { line: 3, column: 1 });
});

test("見えている文字列が、元の Markdown と違えば(強調・リンクをまたぐ)、block", () => {
  const text = "これは **強調** です";
  const loc = locate(text, 0, "これは 強調 です"); // 表示では、** が消えている
  assert.equal(loc.precision, "block");
  assert.equal(loc.expect, text);
});

test("強調の内側だけを選べば、exact", () => {
  const text = "これは **強調** です";
  const loc = locate(text, 0, "強調");
  assert.equal(loc.precision, "exact");
  // 「これは **」は 6 文字なので、「強調」は 7 桁目から
  assert.deepEqual(loc.range.start, { line: 1, column: 7 });
});

test("選択がなければ、block(ブロック全体)", () => {
  const loc = locate("一行目\n二行目", 0, "");
  assert.equal(loc.precision, "block");
  assert.deepEqual(loc.range.end, { line: 2, column: 4 });
  assert.equal(loc.expect, "一行目\n二行目");
});

test("選択の前後の空白は、無視する", () => {
  const loc = locate("a bb c", 0, "  bb \n");
  assert.equal(loc.precision, "exact");
  assert.equal(loc.expect, "bb");
});

test("CRLF の文書: 行・桁は CR を数えず、expect は LF にそろう", () => {
  const text = "一行目\r\n二行目\r\n\r\n三行目";
  const b = { start: 0, end: text.indexOf("\r\n\r\n") };
  const loc = locateInSource({
    path: "a.md",
    text,
    version: 1,
    blockStart: b.start,
    blockEnd: b.end,
    selection: "",
  });
  assert.equal(loc.expect, "一行目\n二行目");
  assert.deepEqual(loc.range.end, { line: 2, column: 4 });
  const exact = locateInSource({
    path: "a.md",
    text,
    version: 1,
    blockStart: b.start,
    blockEnd: b.end,
    selection: "二行目",
  });
  assert.deepEqual(exact.range.start, { line: 2, column: 1 });
});

test("絵文字を含む行でも、桁(コードポイント)が、Emacs の文字の数と一致する", () => {
  const text = "😀😀 target 😀";
  const loc = locate(text, 0, "target");
  assert.equal(loc.precision, "exact");
  assert.deepEqual(loc.range.start, { line: 1, column: 4 });
  assert.deepEqual(loc.range.end, { line: 1, column: 10 });
});

test("長い expect は、先頭の 500 コードポイントだけにして、truncated を立てる", () => {
  const text = "あ".repeat(EXPECT_LIMIT + 50);
  const loc = locate(text, 0, "");
  assert.equal(Array.from(loc.expect).length, EXPECT_LIMIT);
  assert.equal(loc.expectTruncated, true);
  assert.deepEqual(loc.range.end, { line: 1, column: EXPECT_LIMIT + 51 });
});

test("前後の文脈は、サロゲートペアを途中で切らない", () => {
  const text = "😀".repeat(CONTEXT_LENGTH) + "X" + "😀".repeat(CONTEXT_LENGTH);
  const loc = locate(text, 0, "X");
  for (const s of [loc.context.before, loc.context.after]) {
    assert.doesNotMatch(s, /[\ud800-\udbff]$|^[\udc00-\udfff]/);
  }
});

test("uniqueMatch: なし・1 か所・複数(重なりも)", () => {
  assert.equal(uniqueMatch("abc", "x"), null);
  assert.equal(uniqueMatch("abc", "b"), 1);
  assert.equal(uniqueMatch("aaa", "aa"), null); // 重なる 2 か所
  assert.equal(uniqueMatch("abc", ""), null);
});
