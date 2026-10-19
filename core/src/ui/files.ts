// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Input fields for opening files: `C-x C-f` (path completion starting from the base directory) and
// `C-x p f` (recursive listing under the project root). docs/dev/buffer-model.md §5, §6.

import type { DirEntry, TreeListing } from "../host.ts";
import { abbreviateHome, joinPath, resolveInput } from "../paths.ts";
import type { PromptChoice, PromptSource } from "./minibuffer.ts";
import type { AppContext } from "./context.ts";
import { currentProjectRoot, defaultDirectory } from "./directory.ts";

/** Directories first, then ascending by name. Directories get a trailing `/`. */
function entryNames(entries: readonly DirEntry[]): string[] {
  return [...entries]
    .sort((a, b) => (a.dir === b.dir ? a.name.localeCompare(b.name) : a.dir ? -1 : 1))
    .map((e) => (e.dir ? `${e.name}/` : e.name));
}

/** Directory string shown in the input field (shortened with `~/`, with a trailing `/`). */
export function displayDir(dir: string, home: string): string {
  const short = abbreviateHome(dir, home);
  return short.endsWith("/") ? short : `${short}/`;
}

/** Whether the input is "path-shaped" (involves changing the base). */
const isPathLike = (text: string): boolean => /^(\/|~|\.\.?\/)/.test(text);

/**
 * `C-x C-f`: an input field starting from the base directory. Candidates are the `.md` files and subdirectories
 * of the directory already typed (not recursive). Choosing a directory and pressing RET enters it.
 * @returns absolute path of the file to open. null if cancelled.
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
 * `C-x p f`: lists `.md` files recursively under the project root (found by ascending to VCS markers; the base directory if none)
 * and narrows them down.
 * Typing `../`, `~/` or an absolute path switches the starting point to that directory (no ascending after switching) (any file can be reached).
 * When the base is `~` or `/`, it does not recurse and lists one level (the shell refuses).
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
  /** Derives from the input the base directory and the part that narrows the candidates. */
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
