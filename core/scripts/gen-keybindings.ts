// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// docs/user/keybindings.md を、コード(標準のキー割り当てと、コマンドの説明)から生成する。
// 使い方: node scripts/gen-keybindings.ts          生成して、書き込む
//         node scripts/gen-keybindings.ts --check  最新か、検査する(違えば、終了コード 1)

import { readFileSync, writeFileSync } from "node:fs";
import { keysByCommand } from "../src/keybindings.ts";
import { COMMAND_DOCS, COMMAND_NAMES } from "../src/ui/commands.ts";
import { DEFAULT_BINDINGS } from "../src/ui/keymap.ts";

const target = new URL("../../docs/user/keybindings.md", import.meta.url);

// 利用者向けの文書では、コマンドを機能別に並べる(`C-h b` の一覧は、コマンド名順のまま)。
// すべてのコマンドが、ちょうど 1 つのグループに属していなければならない(足し忘れると、生成が失敗する)。
const GROUPS: readonly { title: string; commands: readonly string[] }[] = [
  {
    title: "Files and buffers",
    commands: [
      "find-file",
      "project-find-file",
      "switch-buffer",
      "kill-buffer",
      "project-switch-to-buffer",
      "project-kill-buffers",
    ],
  },
  {
    title: "Reference history and links",
    commands: [
      "back",
      "forward",
      "beginning-of-history",
      "end-of-history",
      "next-link",
      "prev-link",
      "follow-link",
    ],
  },
  {
    title: "Scrolling and position",
    commands: [
      "scroll-line-down",
      "scroll-line-up",
      "scroll-page-down",
      "scroll-page-up",
      "beginning-of-document",
      "end-of-document",
      "goto-line",
    ],
  },
  {
    title: "Headings",
    commands: [
      "next-heading",
      "previous-heading",
      "up-heading",
      "forward-same-level",
      "backward-same-level",
      "goto-heading",
    ],
  },
  {
    title: "Search",
    commands: ["isearch-forward", "isearch-backward", "search-project", "project-find-regexp"],
  },
  {
    title: "Windows",
    commands: [
      "split-below",
      "split-right",
      "delete-window",
      "delete-other-windows",
      "other-window",
      "enlarge-window",
      "shrink-window-if-larger-than-buffer",
      "enlarge-window-horizontally",
      "shrink-window-horizontally",
    ],
  },
  {
    title: "Frames",
    commands: ["make-frame", "delete-frame", "other-frame", "delete-other-frames"],
  },
  {
    title: "Document tools",
    commands: ["count-words", "toggle-follow-updates", "edit-in-editor"],
  },
  {
    title: "Remembered locations",
    commands: ["forget-remembered-path", "forget-remembered-site"],
  },
  {
    title: "Commands and help",
    commands: ["execute-command", "describe-bindings", "keyboard-quit"],
  },
];

const grouped = GROUPS.flatMap((g) => g.commands);
const missing = COMMAND_NAMES.filter((c) => !grouped.includes(c));
const unknown = grouped.filter((c) => !(COMMAND_NAMES as readonly string[]).includes(c));
const repeated = grouped.filter((c, i) => grouped.indexOf(c) !== i);
if (missing.length || unknown.length || repeated.length) {
  console.error(
    `gen-keybindings.ts の GROUPS が、コマンドの一覧と合っていません。足りない: [${missing}]、存在しない: [${unknown}]、重複: [${repeated}]`,
  );
  process.exit(1);
}

/** Markdown の表の中に置く文字列(`|` と改行を、壊さない形にする)。 */
const cell = (s: string): string => s.replace(/\|/g, "\\|").replace(/\n/g, " ");

const keys = keysByCommand(DEFAULT_BINDINGS);
const sections = GROUPS.map(({ title, commands }) => {
  const rows = commands.map((command) => {
    const shown = (keys.get(command) ?? []).map((k) => `\`${k}\``).join(", ");
    return `| ${shown || "(unbound; use `M-x`)"} | \`${command}\` | ${cell(COMMAND_DOCS[command as keyof typeof COMMAND_DOCS] ?? "")} |`;
  });
  return `## ${title}\n\n| Key | Command | Description |\n| --- | --- | --- |\n${rows.join("\n")}\n`;
}).join("\n");

const generated = `<!-- 自動生成: core/scripts/gen-keybindings.ts。直接編集しない(コードの変更に合わせて、再生成する) -->

# Key bindings

The default key bindings of HyperBuf, grouped by function. \`C-h b\` in the app shows the same commands (in alphabetical order, with any configuration problems).
Every command can also be run by name with \`M-x\`.

Bindings can be changed with \`keybindings\` in \`config.json\` (\`null\` removes a default binding); see [configuration.md](configuration.md).
For an introduction to the basic operations, see [getting-started.md](getting-started.md).

${sections}
## Key notation

- \`C-x\`: hold Control and press x. \`M-x\`: hold Meta (Option on macOS) and press x. \`s-[\`: hold Command and press \`[\`. \`S-TAB\`: Shift + Tab.
- \`C-x 2\`: press \`C-x\`, then \`2\` (a prefix key).
- Symbols are judged by the physical key (US layout). \`M-<\` is Option + Shift + \`,\`.
- In an input field (the minibuffer), \`C-f\` / \`C-b\` / \`C-a\` / \`C-e\` move the cursor in the text again. Confirm with \`RET\`, cancel with \`C-g\`, choose a candidate with \`C-n\` / \`C-p\`, and recall the input history with \`M-p\` / \`M-n\`.
`;

if (process.argv.includes("--check")) {
  const current = (() => {
    try {
      return readFileSync(target, "utf8");
    } catch {
      return "";
    }
  })();
  if (current !== generated) {
    console.error(
      "docs/user/keybindings.md が、コードと食い違っています。node scripts/gen-keybindings.ts で、再生成してください。",
    );
    process.exit(1);
  }
} else {
  writeFileSync(target, generated);
  console.log("docs/user/keybindings.md を生成しました");
}
