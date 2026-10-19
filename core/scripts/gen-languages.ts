// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// docs/user/syntax-highlighting.md を、文法の一覧(src/grammars.ts)から生成する。
// 使い方: node scripts/gen-languages.ts          生成して、書き込む
//         node scripts/gen-languages.ts --check  最新か、検査する(違えば、終了コード 1)

import { readFileSync, writeFileSync } from "node:fs";
import type { Grammar } from "@wooorm/starry-night";
import { EAGER, LAZY } from "../src/grammars.ts";

const target = new URL("../../docs/user/syntax-highlighting.md", import.meta.url);

const lazyGrammars = await Promise.all(LAZY.map((g) => g.load()));
const lazyScopes = new Set(lazyGrammars.map((g) => g.scopeName));

const row = (g: Grammar, mode: string): string => {
  const names = g.names.map((n) => `\`${n}\``).join(", ");
  const exts = g.extensions.length > 0 ? g.extensions.map((e) => `\`${e}\``).join(" ") : "";
  return `| ${names} | ${exts} | ${mode} |`;
};

const rows = [
  ...EAGER.map((g) => ({ g, mode: "常時" })),
  ...lazyGrammars.map((g) => ({ g, mode: "必要時に読込" })),
]
  .filter(({ g }) => g.names.length > 0)
  .filter(({ g }, i, all) => all.findIndex((x) => x.g.scopeName === g.scopeName) === i)
  .sort((a, b) => (a.g.names[0] as string).localeCompare(b.g.names[0] as string))
  .map(({ g, mode }) => row(g, lazyScopes.has(g.scopeName) ? "必要時に読込" : mode));

const generated = `<!-- 自動生成: core/scripts/gen-languages.ts。直接編集しない(core/src/grammars.ts を変えたら、\`npm run languages\` で再生成する) -->

# シンタックスハイライト

コードブロックの言語の指定(\` \`\`\`elisp \`)で、GitHub と同じ文法(starry-night)で着色します。${rows.length} 言語に対応しています。
指定には、下の「指定できる名前」のどれか(大文字小文字は区別しない)か、拡張子(\` \`\`\`.el \`)を使えます。
言語の指定がない、または一覧にない場合は、着色しません(文書は、そのまま表示されます)。
\`mermaid\` は着色ではなく、図として描画します。

「文法の読込」は、文法をいつ読み込むかを表します。「必要時に読込」の言語は、文法が大きいため、その言語のコードブロックがある文書を開いたときだけ読み込みます(初めて開くときに、わずかに時間がかかることがあります)。

| 指定できる名前 | 拡張子 | 文法の読込 |
| --- | --- | --- |
${rows.join("\n")}
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
      "docs/user/syntax-highlighting.md が、コードと食い違っています。node scripts/gen-languages.ts で、再生成してください。",
    );
    process.exit(1);
  }
} else {
  writeFileSync(target, generated);
}
