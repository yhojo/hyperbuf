// 文書内のインクリメンタル検索(C-s / C-r)の、検索の部分。DOM に依存しない純粋な関数。

/** 検索語に大文字が含まれるときだけ、大文字小文字を区別する(Emacs の既定の動作)。 */
export function isCaseSensitive(query: string): boolean {
  return query !== query.toLowerCase();
}

/** すべての一致の開始位置(重ならない一致。一致の末尾から、次を探す)。 */
export function findAll(text: string, query: string, caseSensitive: boolean): number[] {
  if (!query) return [];
  const haystack = caseSensitive ? text : text.toLowerCase();
  const needle = caseSensitive ? query : query.toLowerCase();
  const found: number[] = [];
  let from = 0;
  for (;;) {
    const i = haystack.indexOf(needle, from);
    if (i < 0) return found;
    found.push(i);
    from = i + Math.max(needle.length, 1);
  }
}

export interface Step {
  /** 選ぶ一致の、`matches` の中での番号。一致がなければ null。 */
  index: number | null;
  /** 端まで行って、反対の端に戻ったか(Emacs の "Wrapped")。 */
  wrapped: boolean;
}

/**
 * 次(direction = 1)または前(-1)の一致。`current` は、いま選んでいる一致の番号(なければ null)。
 * 端に着いたら、反対の端に戻る。
 */
export function step(count: number, current: number | null, direction: 1 | -1): Step {
  if (count === 0) return { index: null, wrapped: false };
  if (current === null) return { index: direction === 1 ? 0 : count - 1, wrapped: false };
  const next = current + direction;
  if (next >= count) return { index: 0, wrapped: true };
  if (next < 0) return { index: count - 1, wrapped: true };
  return { index: next, wrapped: false };
}

/**
 * 入力が変わったとき(または、検索を始めたとき)に、最初に選ぶ一致: 基準の位置(`from`)以降の、最初の一致。
 * なければ、反対の端に戻る(wrapped)。方向が後ろ向きなら、`from` 以前の、最後の一致。
 */
export function firstMatch(matches: readonly number[], from: number, direction: 1 | -1): Step {
  if (matches.length === 0) return { index: null, wrapped: false };
  if (direction === 1) {
    const i = matches.findIndex((m) => m >= from);
    return i < 0 ? { index: 0, wrapped: true } : { index: i, wrapped: false };
  }
  for (let i = matches.length - 1; i >= 0; i--) {
    if ((matches[i] ?? Infinity) <= from) return { index: i, wrapped: false };
  }
  return { index: matches.length - 1, wrapped: true };
}
