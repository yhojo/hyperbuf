// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Absolute path operations (pure functions with no DOM or shell dependency). A buffer's identity is the normalized absolute path.
// Does not touch the file system (the shell resolves symbolic links).

/** Resolves `.`, `..` and duplicate `/`. Does not go above `/`. Handles absolute paths only. */
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

/** Turns `~` and `~/…` into the host's directory (anything else is left as is). */
export function expandHome(path: string, home: string): string {
  if (path === "~") return home;
  return path.startsWith("~/") ? `${home}${path.slice(1)}` : path;
}

/** Shortens paths under the host's directory with `~` (for display). */
export function abbreviateHome(path: string, home: string): string {
  if (path === home) return "~";
  return home !== "/" && path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

/**
 * Turns an input string into an absolute path. Expands `~/`; if not absolute, treats it as relative to `base`.
 * A trailing `/` is kept (to tell a directory specification apart while typing).
 */
export function resolveInput(text: string, base: string, home: string): string {
  const expanded = expandHome(text, home);
  const abs = expanded.startsWith("/") ? expanded : `${base.replace(/\/$/, "")}/${expanded}`;
  const normalized = normalizePath(abs);
  return abs.endsWith("/") && normalized !== "/" ? `${normalized}/` : normalized;
}

/** Whether `path` is inside `dir` (or is `dir` itself). Judged on separator boundaries (`/tmp` does not match `/tmp2`). */
export function isInside(path: string, dir: string): boolean {
  if (dir === "/") return true;
  return path === dir || path.startsWith(`${dir}/`);
}
