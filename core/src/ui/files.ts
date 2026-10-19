// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// ファイルを開く入力欄。`C-x C-f`(基準のディレクトリから始まるパス補完)と、
// `C-x p f`(基準のディレクトリ以下の再帰の一覧)。docs/project-model.md §3。

import type { DirEntry, TreeListing } from "../host.ts";
import { abbreviateHome, joinPath, resolveInput } from "../paths.ts";
import type { PromptChoice, PromptSource } from "./minibuffer.ts";
import type { AppContext } from "./context.ts";
import { currentProjectRoot, defaultDirectory } from "./directory.ts";

/** ディレクトリが先、名前の昇順。ディレクトリは、末尾に `/`。 */
function entryNames(entries: readonly DirEntry[]): string[] {
  return [...entries]
    .sort((a, b) => (a.dir === b.dir ? a.name.localeCompare(b.name) : a.dir ? -1 : 1))
    .map((e) => (e.dir ? `${e.name}/` : e.name));
}

/** 入力欄に出す、ディレクトリの文字列(`~/` で短縮し、末尾に `/`)。 */
export function displayDir(dir: string, home: string): string {
  const short = abbreviateHome(dir, home);
  return short.endsWith("/") ? short : `${short}/`;
}

/** 入力が「パスの形」(基準の変更を伴う)か。 */
const isPathLike = (text: string): boolean => /^(\/|~|\.\.?\/)/.test(text);

/**
 * `C-x C-f`: 基準のディレクトリから始まる入力欄。候補は、入力済みのディレクトリの、
 * `.md` とサブディレクトリ(再帰しない)。ディレクトリを選んで RET で、その中に入る。
 * @returns 開くファイルの絶対パス。取り消したら null。
 */
export async function promptFindFile(ctx: AppContext): Promise<string | null> {
  const { host, minibuffer, echo } = ctx;
  const base = defaultDirectory(ctx);
  const home = host.home;
  const source = async (text: string): Promise<PromptSource> => {
    const cut = text.lastIndexOf("/") + 1;
    const prefix = text.slice(0, cut);
    const fragment = text.slice(cut);
    const dir = resolveInput(prefix === "" ? "./" : prefix, base, home);
    const listing = await host.listDirectory(dir, { hidden: fragment.startsWith(".") });
    return { items: entryNames(listing.entries), prefix, fragment };
  };
  const choose = (picked: string | null, text: string, src: PromptSource): PromptChoice => {
    if (picked) {
      const typed = src.prefix + picked;
      return picked.endsWith("/") ? { text: typed } : { done: resolveInput(typed, base, home) };
    }
    if (text === "" || text.endsWith("/")) return null;
    const abs = resolveInput(text, base, home);
    if (!abs.endsWith(".md")) {
      echo.message("Only Markdown (.md) files can be opened");
      return null;
    }
    return { done: abs };
  };
  return minibuffer.prompt("Find file: ", [], {
    initial: displayDir(base, home),
    history: "find-file",
    source,
    choose,
  });
}

/**
 * `C-x p f`: プロジェクト・ルート(VCS の目印をさかのぼって求める。なければ基準のディレクトリ)
 * 以下の `.md` を、再帰で一覧にして絞り込む。
 * `../`・`~/`・絶対パスを入力すると、起点がそのディレクトリに切り替わる(切り替えたあとは、さかのぼらない)(任意のファイルに届く)。
 * 基準が `~` や `/` のときは、再帰せず、1 階層の一覧にする(シェルが拒否する)。
 */
export async function promptFindFileRecursive(ctx: AppContext): Promise<string | null> {
  const { host, minibuffer, echo } = ctx;
  const start = await currentProjectRoot(ctx);
  const home = host.home;
  const trees = new Map<string, Promise<TreeListing>>();
  const noticed = new Set<string>();
  const treeOf = (dir: string): Promise<TreeListing> => {
    let tree = trees.get(dir);
    if (!tree) {
      tree = host.listTree(dir);
      trees.set(dir, tree);
    }
    return tree;
  };
  /** 入力から、基準のディレクトリと、候補を絞り込む部分を求める。 */
  const split = (text: string): { dir: string; prefix: string; fragment: string } => {
    if (!isPathLike(text)) return { dir: start, prefix: "", fragment: text };
    const cut = text.lastIndexOf("/") + 1;
    const prefix = text.slice(0, cut);
    return {
      dir: resolveInput(prefix || "./", start, home).replace(/(.)\/$/, "$1"),
      prefix,
      fragment: text.slice(cut),
    };
  };
  const source = async (text: string): Promise<PromptSource> => {
    const { dir, prefix, fragment } = split(text);
    const tree = await treeOf(dir);
    if ((tree.refused || tree.truncated || tree.error) && !noticed.has(dir)) {
      noticed.add(dir);
      echo.message(
        tree.error
          ? `Cannot list: ${tree.error}`
          : tree.refused
            ? `${tree.refused} (listing one level only)`
            : "Listing truncated at the file limit",
      );
    }
    if (tree.refused) {
      const listing = await host.listDirectory(dir, { hidden: false });
      return { items: entryNames(listing.entries), prefix, fragment };
    }
    return { items: tree.files, prefix, fragment };
  };
  const choose = (picked: string | null, text: string, src: PromptSource): PromptChoice => {
    if (!picked) return null;
    if (picked.endsWith("/")) return { text: src.prefix + picked };
    const { dir } = split(text);
    return { done: joinPath(dir, picked) };
  };
  return minibuffer.prompt(`Find file in ${displayDir(start, home)}: `, [], {
    initial: "",
    history: "find-file-tree",
    source,
    choose,
  });
}
