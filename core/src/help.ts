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
    "# Key bindings",
    "",
    "`C-h b` shows this list. Bindings can be changed with `keybindings` in `config.json` (`null` removes a default binding).",
    "Commands can be run by name with `M-x`.",
    "",
  ];
  if (problems.length) {
    lines.push("## Configuration problems", "", "The following settings were ignored.", "");
    for (const p of problems) lines.push(`- ${p.replace(/\n/g, " ")}`);
    lines.push("");
  }
  lines.push("## Bound commands", "", "| Key | Command | Description |", "| --- | --- | --- |");
  for (const command of bound) {
    const shown = (keys.get(command) ?? []).map((k) => `\`${k}\``).join(", ");
    lines.push(`| ${shown} | \`${command}\` | ${cell(docs[command] ?? "")} |`);
  }
  lines.push(
    "",
    "## Unbound commands (run with `M-x`)",
    "",
    "| Command | Description |",
    "| --- | --- |",
  );
  for (const command of unbound) lines.push(`| \`${command}\` | ${cell(docs[command] ?? "")} |`);
  lines.push("");
  return lines.join("\n");
}
