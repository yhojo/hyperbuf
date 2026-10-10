// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 絶対パスの操作(DOM やシェルに依存しない純粋な関数)。バッファの識別は、正規化した絶対パス。
// ファイルシステムには触れない(シンボリックリンクの解決は、シェルが行う)。

/** `.` と `..` と重複した `/` を解決する。`/` より上へは行かない。絶対パスだけを扱う。 */
export function normalizePath(path: string): string {
  const out: string[] = [];
  for (const seg of path.split("/")) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") out.pop();
    else out.push(seg);
  }
  return "/" + out.join("/");
}

export function dirname(path: string): string {
  const i = path.lastIndexOf("/");
  return i <= 0 ? "/" : path.slice(0, i);
}

export function basename(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

export function joinPath(dir: string, rel: string): string {
  return normalizePath(rel.startsWith("/") ? rel : `${dir}/${rel}`);
}

/** `~` と `~/…` をホストのディレクトリにする(それ以外は、そのまま)。 */
export function expandHome(path: string, home: string): string {
  if (path === "~") return home;
  return path.startsWith("~/") ? `${home}${path.slice(1)}` : path;
}

/** ホストのディレクトリ以下を `~` で短縮する(表示用)。 */
export function abbreviateHome(path: string, home: string): string {
  if (path === home) return "~";
  return home !== "/" && path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

/**
 * 入力欄の文字列を、絶対パスにする。`~/` は展開し、絶対パスでなければ、`base` からの相対とみなす。
 * 末尾の `/` は残す(ディレクトリの指定を、入力中に区別するため)。
 */
export function resolveInput(text: string, base: string, home: string): string {
  const expanded = expandHome(text, home);
  const abs = expanded.startsWith("/") ? expanded : `${base.replace(/\/$/, "")}/${expanded}`;
  const normalized = normalizePath(abs);
  return abs.endsWith("/") && normalized !== "/" ? `${normalized}/` : normalized;
}

/** `path` が `dir` の中(または `dir` そのもの)か。区切りの境界で判定する(`/tmp` は `/tmp2` に一致しない)。 */
export function isInside(path: string, dir: string): boolean {
  if (dir === "/") return true;
  return path === dir || path.startsWith(`${dir}/`);
}
