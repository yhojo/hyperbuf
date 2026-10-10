// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// ファイル名などのあいまい絞り込み。空白区切りの語をすべて含む候補を、近さの順に返す。
// 語は、(1) ファイル名への部分一致 > (2) パス全体への部分一致 > (3) 飛び飛びの一致(文字の並びが保たれる)、の順に高く評価する。

function score(text: string, lower: string, tokens: string[]): number | null {
  const base = lower.slice(lower.lastIndexOf("/") + 1);
  let total = 0;
  for (const t of tokens) {
    let i = base.indexOf(t);
    if (i >= 0) {
      total += 100 + (i === 0 ? 20 : 0) - base.length * 0.1;
      continue;
    }
    i = lower.indexOf(t);
    if (i >= 0) {
      total += 60 - i * 0.05;
      continue;
    }
    let pos = -1;
    let prev = -2;
    let gaps = 0;
    for (const ch of t) {
      pos = lower.indexOf(ch, pos + 1);
      if (pos < 0) return null;
      if (pos !== prev + 1) gaps += 1;
      prev = pos;
    }
    total += 30 - gaps * 3;
  }
  return total - text.length * 0.01;
}

/** 一致した文字の範囲 [開始, 終了)(候補の強調表示用)。語ごとに、`score` と同じ優先順で、最初に見つかった場所。 */
export function matchRanges(candidate: string, query: string): [number, number][] {
  const lower = candidate.toLowerCase();
  const base = lower.lastIndexOf("/") + 1;
  const ranges: [number, number][] = [];
  for (const t of query.toLowerCase().split(/\s+/).filter(Boolean)) {
    let i = lower.indexOf(t, base);
    if (i < 0) i = lower.indexOf(t);
    if (i >= 0) {
      ranges.push([i, i + t.length]);
      continue;
    }
    let pos = -1; // 飛び飛びの一致: 1 文字ずつ
    for (const ch of t) {
      pos = lower.indexOf(ch, pos + 1);
      if (pos < 0) break;
      ranges.push([pos, pos + ch.length]);
    }
  }
  return mergeRanges(ranges);
}

/** 重なる・隣り合う範囲を、まとめる。 */
function mergeRanges(ranges: [number, number][]): [number, number][] {
  const sorted = [...ranges].sort((a, b) => a[0] - b[0]);
  const out: [number, number][] = [];
  for (const [s, e] of sorted) {
    const last = out[out.length - 1];
    if (last && s <= last[1]) last[1] = Math.max(last[1], e);
    else out.push([s, e]);
  }
  return out;
}

export function fuzzyFilter(candidates: readonly string[], query: string, limit = 8): string[] {
  const tokens = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!tokens.length) return candidates.slice(0, limit);
  const top: [number, string][] = [];
  for (const c of candidates) {
    const s = score(c, c.toLowerCase(), tokens);
    if (s === null) continue;
    // 上位 limit 件だけを保つ(候補が数千でも並べ替えを避ける)
    const worst = top[top.length - 1];
    if (top.length < limit || (worst && s > worst[0])) {
      top.push([s, c]);
      top.sort((a, b) => b[0] - a[0]);
      if (top.length > limit) top.pop();
    }
  }
  return top.map(([, c]) => c);
}
