// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Contents of `describe-bindings` (C-h b). Shown as Markdown in a virtual buffer. A pure function with no DOM dependency.

import { keysByCommand } from "./keybindings.ts";

export interface HelpInput {
  /** Command name -> description (all commands). */
  docs: Readonly<Record<string, string>>;
  bindings: Readonly<Record<string, string>>;
  problems: readonly string[];
}

/** A string to place inside a Markdown table (makes `|` and newlines safe). */
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
