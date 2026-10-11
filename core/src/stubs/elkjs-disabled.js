// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// elkjs(EPL-2.0)の代わりに、バンドルに入れる空の実装。Mermaid の ELK レイアウト(`layout: elk` / `flowchart-elk`)だけが
// 使う。ELK を使う図は、レイアウトの呼び出しで失敗し、図の位置にエラーとして表示される(文書全体は止まらない)。
// Mermaid は、ELK のチャンクを評価するとき(通常の図でも起こる)に、`new ELK()` を呼ぶので、
// コンストラクタでは投げない。どのメソッドも、呼ばれたときに、失敗した Promise を返す。
// 理由: docs/license-options.md(EPL-2.0 の同梱を避け、ライセンスの選択肢を広く保つ。約 1.5 MB のチャンクも減る)。
const unsupported = () =>
  Promise.reject(new Error("ELK レイアウトは、HyperBuf では使えません(layout: elk は未対応)"));

export default class ELK {
  constructor() {
    return new Proxy(this, {
      // await や Promise.resolve が、thenable と取り違えないように
      get: (_target, property) => (property === "then" ? undefined : unsupported),
    });
  }
}
