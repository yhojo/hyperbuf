// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// docs/keybindings.md を、コード(標準のキー割り当てと、コマンドの説明)から生成する。
// 使い方: node scripts/gen-keybindings.ts          生成して、書き込む
//         node scripts/gen-keybindings.ts --check  最新か、検査する(違えば、終了コード 1)

import { readFileSync, writeFileSync } from "node:fs";
import { renderBindingsHelp } from "../src/help.ts";
import { COMMAND_DOCS } from "../src/ui/commands.ts";
import { DEFAULT_BINDINGS } from "../src/ui/keymap.ts";

const target = new URL("../../docs/keybindings.md", import.meta.url);

const body = renderBindingsHelp({ docs: COMMAND_DOCS, bindings: DEFAULT_BINDINGS, problems: [] });
const generated = `<!-- 自動生成: core/scripts/gen-keybindings.ts。直接編集しない(コードの変更に合わせて、再生成する) -->

${body}
## キーの表記

- \`C-x\`: Control を押しながら x。\`M-x\`: Meta(macOS では Option)を押しながら x。\`s-[\`: Command を押しながら \`[\`。\`S-TAB\`: Shift + Tab。
- \`C-x 2\`: \`C-x\` を押したあとで、\`2\` を押す(プレフィックス)。
- 記号は、物理キーで判断する(US 配列)。\`M-<\` は、Option + Shift + \`,\`。
- 入力欄(ミニバッファ)の中では、\`C-f\` / \`C-b\` / \`C-a\` / \`C-e\` は、文字の移動に戻る。確定は \`RET\`、取消は \`C-g\`、候補の選択は \`C-n\` / \`C-p\`、入力の履歴は \`M-p\` / \`M-n\`。

設定で変える方法は、[configuration.md](configuration.md)。
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
      "docs/keybindings.md が、コードと食い違っています。node scripts/gen-keybindings.ts で、再生成してください。",
    );
    process.exit(1);
  }
} else {
  writeFileSync(target, generated);
  console.log("docs/keybindings.md を生成しました");
}
