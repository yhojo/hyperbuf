// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// バッファの名前(画面に出す名前)。識別は絶対パスで、名前は、Emacs の uniquify と同じ考え方で決める
// (docs/buffer-model.md §3): 基本はファイル名。同じ名前が複数あるときだけ、親ディレクトリを足す。
// 形式は `post-forward-angle-brackets`(`README.md<docs>`)。

import { abbreviateHome, basename } from "./paths.ts";

/**
 * 仮想バッファ(ファイルに対応しない)の識別。`*種類: 名前 @ 起点のディレクトリ*`。
 * 起点があるもの(検索結果)は、基準のディレクトリ(`default-directory`)を持つ。
 */
export function virtualPath(label: string, dir?: string): string {
  return dir ? `*${label} @ ${dir}*` : `*${label}*`;
}

export interface VirtualParts {
  /** `*` を除いた、見出し(例: `search: foo`)。 */
  label: string;
  /** 起点のディレクトリ(なければ undefined)。 */
  dir?: string;
}

export function parseVirtualPath(path: string): VirtualParts {
  const inner = path.slice(1, -1);
  const at = inner.lastIndexOf(" @ /");
  return at < 0 ? { label: inner } : { label: inner.slice(0, at), dir: inner.slice(at + 3) };
}

/** 識別から、そのまま表示できる基本の名前(重複の区別は、まだ付けない)。 */
function baseName(path: string): string {
  if (!path.startsWith("*")) return basename(path);
  return `*${parseVirtualPath(path).label}*`;
}

/** 区別の元になるディレクトリ(ファイルは親、仮想バッファは起点)。なければ、null。 */
function directoryOf(path: string): string | null {
  if (path.startsWith("*")) return parseVirtualPath(path).dir ?? null;
  return path.slice(0, Math.max(path.lastIndexOf("/"), 0)) || "/";
}

/** ディレクトリの末尾から `count` 階層を取る(`/a/b/c` の 2 階層は `b/c`)。ホストのディレクトリは `~`。 */
function suffix(dir: string, count: number, home: string): string {
  const abbreviated = abbreviateHome(dir, home);
  const parts = abbreviated.split("/").filter((p, i) => p !== "" || i === 0);
  if (count >= parts.length) return abbreviated === "/" ? "/" : abbreviated;
  return parts.slice(-count).join("/");
}

/**
 * すべての(開いている)バッファの識別から、表示名を求める。
 * 同じ基本の名前が複数あるものは、区別がつく最小の階層まで、ディレクトリの末尾側を足す。
 * 仮想バッファで起点があるものは、衝突しなくても、起点を足す(`*search: foo*<docs>`)。
 */
export function uniquifyNames(paths: readonly string[], home: string): Map<string, string> {
  const result = new Map<string, string>();
  const groups = new Map<string, string[]>();
  for (const path of paths) {
    const base = baseName(path);
    groups.set(base, [...(groups.get(base) ?? []), path]);
  }
  for (const [base, members] of groups) {
    for (const path of members) {
      const dir = directoryOf(path);
      const alwaysShow = path.startsWith("*") && dir !== null;
      if ((members.length === 1 && !alwaysShow) || dir === null) {
        result.set(path, base);
        continue;
      }
      // 同じ名前の他のバッファの接尾辞と、重ならない最小の階層を探す
      const others = members.filter((m) => m !== path).map(directoryOf);
      let count = 1;
      const max = dir.split("/").length;
      while (count < max) {
        const mine = suffix(dir, count, home);
        if (!others.some((o) => o !== null && suffix(o, count, home) === mine)) break;
        count += 1;
      }
      result.set(path, `${base}<${suffix(dir, count, home)}>`);
    }
  }
  return result;
}
