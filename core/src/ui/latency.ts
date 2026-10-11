// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 打鍵から描画までの遅延の計測(ステータス行に、中央値・p95・最大を出す)。

export interface LatencySummary {
  n: number;
  median: number;
  p95: number;
  max: number;
}

export function summarize(samples: readonly number[]): LatencySummary {
  const sorted = [...samples].sort((a, b) => a - b);
  const at = (p: number): number =>
    sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))] ?? 0;
  return { n: sorted.length, median: at(0.5), p95: at(0.95), max: sorted[sorted.length - 1] ?? 0 };
}

export class LatencyRecorder {
  private readonly samples: number[] = [];
  private readonly keep: number;

  constructor(keep = 100) {
    this.keep = keep;
  }

  /** 描画の後(次のフレームの後)の時刻まで待って、t0 からの経過を記録する。 */
  record(t0: number, onUpdate: (ms: number, summary: LatencySummary) => void): void {
    requestAnimationFrame(() =>
      setTimeout(() => {
        const ms = performance.now() - t0;
        this.samples.push(ms);
        if (this.samples.length > this.keep) this.samples.shift();
        onUpdate(ms, summarize(this.samples));
      }, 0),
    );
  }

  all(): readonly number[] {
    return this.samples;
  }
}
