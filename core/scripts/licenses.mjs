// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 同梱するサードパーティのライセンスの洗い出し(docs/history/migration-plan.md の M8)。
//
// 使い方:
//   node scripts/licenses.mjs summary          docs/user/third-party-licenses.md を出力する(一覧)
//   node scripts/licenses.mjs notices <出力先>   アプリに同梱する THIRD-PARTY-NOTICES(全文つき)を出力する
//   node scripts/licenses.mjs check            許可するライセンスだけか、ライセンス文があるか、一覧が最新かを検査する
//
// 対象は「実際にバンドルに入るもの」。esbuild の metafile から、入力になった node_modules のパッケージを求める
// (devDependencies のうち、テストやビルドだけに使うものは、含まれない)。
// 追加: Swift 側(アプリ・CLI)は、サードパーティの依存を持たない。starry-night の文法は、バンドルに入ったものだけの
// ライセンス文を、starry-night の `notice` から取り出す。npm で洗い出せないもの(KaTeX のフォント)は
// legal/extra-licenses.json に書く。

import * as esbuild from "esbuild";
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { buildOptions } from "../build-options.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const repo = resolve(root, "..");
process.chdir(root);

/** 許可するライセンス(SPDX)。ここにないものは、確認が済むまで、検査で失敗する。 */
const ALLOWED_LIST = [
  "MIT",
  "ISC",
  "Apache-2.0",
  "BSD-2-Clause",
  "BSD-3-Clause",
  "0BSD",
  "Unlicense",
  "CC0-1.0",
  "BlueOak-1.0.0",
  "OFL-1.1",
  // starry-night の文法のうち、SPDX で表せない、許容的なもの(ライセンス文は、notice に含まれる)
  "permissive",
  "wtfpl",
  "zlib",
  "public domain",
  "MPL-2.0",
];
const ALLOWED = new Set(ALLOWED_LIST.map((l) => l.toLowerCase()));

const extra = JSON.parse(readFileSync(join(repo, "legal/extra-licenses.json"), "utf8"));

/** SPDX の式(OR / AND)を判定する。OR は、どれか 1 つが許可されていればよい。 */
function allowed(expression) {
  const text = expression.replace(/[()]/g, " ").trim();
  if (text.includes(" OR ")) return text.split(" OR ").some((e) => allowed(e));
  if (text.includes(" AND ")) return text.split(" AND ").every((e) => allowed(e));
  return ALLOWED.has(text.toLowerCase());
}

async function bundledPackages() {
  const result = await esbuild.build({
    ...buildOptions,
    outdir: "/tmp/hyperbuf-licenses",
    write: false,
    metafile: true,
    logLevel: "error",
  });
  const dirs = new Map();
  const grammars = new Set();
  // 出力に実際に残ったもの(ツリーシェイクで捨てられたファイルは、metafile の入力には出るが、配布物には入らない)
  const inBundle = new Set();
  for (const output of Object.values(result.metafile.outputs)) {
    for (const [input, info] of Object.entries(output.inputs)) {
      if (info.bytesInOutput > 0) inBundle.add(input);
    }
  }
  for (const input of inBundle) {
    const i = input.lastIndexOf("node_modules/");
    if (i < 0) continue;
    const rest = input.slice(i + "node_modules/".length).split("/");
    const name = rest[0].startsWith("@") ? `${rest[0]}/${rest[1]}` : rest[0];
    dirs.set(input.slice(0, i + "node_modules/".length) + name, name);
    if (name === "@wooorm/starry-night" && input.includes("/starry-night/lang/")) {
      grammars.add(input.slice(input.indexOf("/lang/") + 1));
    }
  }
  return { dirs, grammars };
}

function licenseOf(pj) {
  if (typeof pj.license === "string") return pj.license;
  if (pj.license?.type) return pj.license.type;
  if (Array.isArray(pj.licenses)) return pj.licenses.map((l) => l.type).join(" OR ");
  return "";
}

const LICENSE_FILE = /^(licen[sc]e|copying|notice)(\.|$|-)/i;

function licenseFiles(dir) {
  return readdirSync(dir)
    .filter((f) => LICENSE_FILE.test(f))
    .sort()
    .map((f) => ({ file: f, text: readFileSync(join(dir, f), "utf8").trim() }));
}

function repositoryOf(pj) {
  const r =
    typeof pj.repository === "string" ? pj.repository : (pj.repository?.url ?? pj.homepage ?? "");
  return r.replace(/^git\+/, "").replace(/\.git$/, "");
}

/** starry-night の notice を、ブロックに分ける({files, source, spdx, text})。 */
function starryNightNotices(grammars) {
  const text = readFileSync(join(root, "node_modules/@wooorm/starry-night/notice"), "utf8");
  const blocks = text.split(/\n={20,}\n/).slice(1);
  const out = [];
  for (const block of blocks) {
    const m =
      /^Files in `starry-night`: (.+)\nFrom source: (.+)\nSPDX: (.+)\n-{20,}\n([\s\S]*)$/.exec(
        block,
      );
    if (!m) continue;
    const files = m[1].split(", ").map((f) => f.trim());
    const used = files.filter((f) => grammars.has(f));
    if (!used.length) continue;
    out.push({ files: used, source: m[2].trim(), spdx: m[3].trim(), text: m[4].trim() });
  }
  return out;
}

async function collect() {
  const { dirs, grammars } = await bundledPackages();
  const packages = [];
  for (const [dir, name] of [...dirs].sort((a, b) => a[1].localeCompare(b[1]))) {
    const pj = JSON.parse(readFileSync(join(root, dir, "package.json"), "utf8"));
    const override = extra.overrides[name];
    packages.push({
      name,
      version: pj.version,
      license: override?.license ?? licenseOf(pj),
      declared: licenseOf(pj),
      override,
      source: repositoryOf(pj),
      files: licenseFiles(join(root, dir)),
    });
    const last = packages[packages.length - 1];
    // ライセンス文のファイルがないパッケージ: MIT の標準の文面に、author を補う(override に copyright を書く)
    if (!last.files.length && override?.copyright && /^MIT$/i.test(last.license)) {
      const template = readFileSync(join(repo, "legal/MIT-template.txt"), "utf8");
      last.files = [
        {
          file: "(補った MIT の文面)",
          text: template.replace("{{COPYRIGHT}}", override.copyright).trim(),
        },
      ];
    }
  }
  return { packages, grammars: starryNightNotices(grammars), grammarFiles: grammars };
}

function problems({ packages, grammars }) {
  const list = [];
  for (const p of packages) {
    if (!p.license) list.push(`${p.name}@${p.version}: ライセンスが分からない`);
    else if (!p.override?.review && !allowed(p.license)) {
      list.push(`${p.name}@${p.version}: 許可していないライセンス: ${p.license}`);
    }
    if (!p.files.length) list.push(`${p.name}@${p.version}: ライセンス文のファイルがない`);
    if (p.override?.review)
      list.push(`${p.name}@${p.version}: 要確認(${p.license}): ${p.override.reason}`);
  }
  for (const g of grammars) {
    if (!allowed(g.spdx))
      list.push(`starry-night の文法 ${g.files[0]} ほか: 許可していないライセンス: ${g.spdx}`);
  }
  return list;
}

function summary(data) {
  const counts = new Map();
  for (const p of data.packages) counts.set(p.license, (counts.get(p.license) ?? 0) + 1);
  const gcounts = new Map();
  for (const g of data.grammars) gcounts.set(g.spdx, (gcounts.get(g.spdx) ?? 0) + g.files.length);
  const lines = [
    "# サードパーティのライセンス(自動生成)",
    "",
    "`node core/scripts/licenses.mjs summary` で生成する。**手で編集しない**(`npm run check` が、最新かを検査する)。",
    "アプリに同梱する全文つきの `THIRD-PARTY-NOTICES` は、`app/macos/scripts/make-app.sh` が、同じスクリプトで生成する。",
    "",
    "対象は、Web コア(`core/dist`)のバンドルに実際に入るもの。Swift 側(アプリ・CLI・プロトコル)は、サードパーティの依存を持たない。",
    "",
    `## 集計(npm のパッケージ ${data.packages.length} 件)`,
    "",
    "| ライセンス | 件数 |",
    "| --- | --- |",
    ...[...counts].sort((a, b) => b[1] - a[1]).map(([l, n]) => `| ${l} | ${n} |`),
    "",
    "- **MIT / ISC / BSD / Apache-2.0** など許容的なライセンスは、著作権表示とライセンス文を、配布物に含めれば足りる。",
    ...data.packages
      .filter((p) => p.override)
      .map(
        (p) =>
          `- **${p.name}**(${p.license}${p.override.review ? "、要確認" : ""}): ${p.override.reason}`,
      ),
    "",
    `## starry-night の文法(バンドルに入った ${data.grammarFiles.size} 件)`,
    "",
    "| ライセンス(SPDX) | 件数 |",
    "| --- | --- |",
    ...[...gcounts].sort((a, b) => b[1] - a[1]).map(([l, n]) => `| ${l} | ${n} |`),
    "",
    "文法ごとの出所とライセンス文は、`THIRD-PARTY-NOTICES` に入る(starry-night の `notice` から、バンドルに入ったものだけを取り出す)。コピーレフト(GPL 系)のものは、ない。",
    "",
    "## その他の同梱物",
    "",
    ...extra.assets.map((a) => `- **${a.name}**(${a.license}): ${a.note}`),
    "",
    "## パッケージの一覧",
    "",
    "| パッケージ | バージョン | ライセンス |",
    "| --- | --- | --- |",
    ...data.packages.map((p) => `| ${p.name} | ${p.version} | ${p.license} |`),
    "",
  ];
  return lines.join("\n");
}

function notices(data) {
  const bar = "=".repeat(80);
  const out = [
    "HyperBuf が同梱している、サードパーティのソフトウェアの著作権表示とライセンス",
    "(THIRD-PARTY NOTICES)",
    "",
    "HyperBuf は、下に挙げるソフトウェアを含んでいます。それぞれのライセンスの条件に従って、",
    "著作権表示とライセンス文を、以下に再掲します。",
    "",
  ];
  for (const p of data.packages) {
    out.push(
      bar,
      `${p.name} ${p.version}`,
      `License: ${p.license}${p.declared !== p.license ? ` (declared: ${p.declared || "none"})` : ""}`,
    );
    if (p.source) out.push(`Source: ${p.source}`);
    if (p.override) out.push(`Note: ${p.override.reason}`);
    for (const f of p.files) out.push("", `--- ${f.file} ---`, f.text);
    out.push("");
  }
  out.push(
    bar,
    "starry-night の文法(TextMate grammars): バンドルに入ったものだけ",
    "Source: https://github.com/wooorm/starry-night",
    "",
  );
  const own = join(root, "node_modules/@wooorm/starry-night/license");
  if (existsSync(own))
    out.push("--- starry-night/license ---", readFileSync(own, "utf8").trim(), "");
  for (const g of data.grammars) {
    out.push(
      `--- ${g.files.join(", ")} ---`,
      `From source: ${g.source}`,
      `SPDX: ${g.spdx}`,
      "",
      g.text,
      "",
    );
  }
  for (const a of extra.assets) {
    out.push(
      bar,
      a.name,
      `License: ${a.license}`,
      `Source: ${a.source}`,
      `Files: ${a.files}`,
      "",
      a.copyright,
      "",
    );
    out.push(readFileSync(join(repo, a.textFile), "utf8").trim(), "");
  }
  return out.join("\n");
}

const [mode, target] = process.argv.slice(2);
const data = await collect();
const summaryFile = join(repo, "docs/user/third-party-licenses.md");

if (mode === "summary") {
  writeFileSync(summaryFile, summary(data));
  console.log(`${summaryFile} を生成しました(${data.packages.length} パッケージ)`);
} else if (mode === "notices") {
  if (!target) throw new Error("出力先を指定してください");
  writeFileSync(target, notices(data));
  console.log(`${target} を生成しました`);
} else if (mode === "check") {
  const found = problems(data).filter((p) => !p.includes("要確認"));
  const reviews = problems(data).filter((p) => p.includes("要確認"));
  const current = existsSync(summaryFile) ? readFileSync(summaryFile, "utf8") : "";
  if (current !== summary(data))
    found.push(
      "docs/user/third-party-licenses.md が古い(node scripts/licenses.mjs summary で生成し直す)",
    );
  for (const r of reviews) console.warn(`注意: ${r}`);
  if (found.length) {
    for (const p of found) console.error(`NG: ${p}`);
    process.exit(1);
  }
  console.log(
    `ライセンスの検査: OK(${data.packages.length} パッケージ、文法 ${data.grammarFiles.size} 件)`,
  );
} else {
  console.error("使い方: licenses.mjs summary | notices <出力先> | check");
  process.exit(2);
}
