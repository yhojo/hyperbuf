// outline-mode 風の見出し移動の判断(docs/interaction-model.md)。DOM に依存しない純粋な関数。
// 「いまの位置」は、画面の上端(scrollTop)。見出しは、文書の先頭から順に並ぶ(tops は、各見出しの上端の位置)。
//
//   C-c C-n  次の見出し        C-c C-p  前の見出し
//   C-c C-f  同じレベルの、次   C-c C-b  同じレベルの、前       C-c C-u  上のレベルの見出しへ
//
// 画面の上端が、見出しの上端に(ほぼ)あるときは、「その見出しにいる」とみなす(EPS の範囲)。

/** 見出しの上端が、画面の上端と同じとみなす誤差(px)。 */
export const EPS = 8;

/** いま、どの見出しの節の中にいるか(最後の、上端が画面の上端以前の見出し)。なければ -1。 */
export function currentIndex(tops: readonly number[], scrollTop: number): number {
  let current = -1;
  for (let i = 0; i < tops.length; i++) {
    if ((tops[i] ?? Infinity) <= scrollTop + EPS) current = i;
    else break;
  }
  return current;
}

/** 次の見出し: 上端が、画面の上端より下にある、最初の見出し。 */
export function nextIndex(tops: readonly number[], scrollTop: number): number | null {
  const i = tops.findIndex((t) => t > scrollTop + EPS);
  return i < 0 ? null : i;
}

/** 前の見出し: 上端が、画面の上端より上にある、最後の見出し。 */
export function previousIndex(tops: readonly number[], scrollTop: number): number | null {
  for (let i = tops.length - 1; i >= 0; i--) {
    if ((tops[i] ?? Infinity) < scrollTop - EPS) return i;
  }
  return null;
}

/** 上のレベルの見出し: いまの節の見出しより前で、レベルが小さい、最も近い見出し。 */
export function upIndex(levels: readonly number[], current: number): number | null {
  const level = levels[current];
  if (level === undefined) return null;
  for (let i = current - 1; i >= 0; i--) {
    if ((levels[i] ?? Infinity) < level) return i;
  }
  return null;
}

/** 同じレベルの、次の見出し。上のレベルの見出しをまたがない(同じ親の、兄弟だけ)。 */
export function sameLevelForward(levels: readonly number[], current: number): number | null {
  const level = levels[current];
  if (level === undefined) return null;
  for (let i = current + 1; i < levels.length; i++) {
    const l = levels[i] ?? Infinity;
    if (l < level) return null;
    if (l === level) return i;
  }
  return null;
}

/** 同じレベルの、前の見出し。上のレベルの見出しをまたがない。 */
export function sameLevelBackward(levels: readonly number[], current: number): number | null {
  const level = levels[current];
  if (level === undefined) return null;
  for (let i = current - 1; i >= 0; i--) {
    const l = levels[i] ?? Infinity;
    if (l < level) return null;
    if (l === level) return i;
  }
  return null;
}
