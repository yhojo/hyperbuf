// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// `describe-bindings`(C-h b)の内容。仮想 buffer に、Markdown として出す。DOM に依存しない純粋な関数。

import { keysByCommand } from "./keybindings.ts";

export interface HelpInput {
  /** コマンド名 → 説明(全コマンド)。 */
  docs: Readonly<Record<string, string>>;
  bindings: Readonly<Record<string, string>>;
  problems: readonly string[];
}

/** Markdown の表の中に置く文字列(`|` と改行を、壊さない形にする)。 */
const cell = (s: string): string => s.replace(/\|/g, "\\|").replace(/\n/g, " ");

export function renderBindingsHelp({ docs, bindings, problems }: HelpInput): string {
  const keys = keysByCommand(bindings);
  const commands = Object.keys(docs).sort();
  const bound = commands.filter((c) => keys.has(c));
  const unbound = commands.filter((c) => !keys.has(c));
  const lines = [
    "# キー割り当て",
    "",
    "`C-h b` で、この一覧を出す。割り当ては、`config.json` の `keybindings` で変えられる(`null` で、標準の割り当てを外す)。",
    "コマンドは、`M-x` から、名前で実行できる。",
    "",
  ];
  if (problems.length) {
    lines.push("## 設定の問題", "", "次の設定は、無視した。", "");
    for (const p of problems) lines.push(`- ${p.replace(/\n/g, " ")}`);
    lines.push("");
  }
  lines.push("## 割り当て済み", "", "| キー | コマンド | 説明 |", "| --- | --- | --- |");
  for (const command of bound) {
    const shown = (keys.get(command) ?? []).map((k) => `\`${k}\``).join("、 ");
    lines.push(`| ${shown} | \`${command}\` | ${cell(docs[command] ?? "")} |`);
  }
  lines.push("", "## キーなし(`M-x` で実行)", "", "| コマンド | 説明 |", "| --- | --- |");
  for (const command of unbound) lines.push(`| \`${command}\` | ${cell(docs[command] ?? "")} |`);
  lines.push("");
  return lines.join("\n");
}
