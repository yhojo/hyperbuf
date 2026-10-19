// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Buffer names (the names shown on screen). Identity is the absolute path; names are decided with the same idea as Emacs's uniquify
// (docs/dev/buffer-model.md §3): basically the file name. Only when several share a name, the parent directory is added.
// The form is `post-forward-angle-brackets` (`README.md<docs>`).

import { abbreviateHome, basename } from "./paths.ts";

/**
 * Identity of a virtual buffer (not tied to a file): `*kind: name @ origin directory*`.
 * One with an origin (search results) has a base directory (`default-directory`).
 */
export function virtualPath(label: string, dir?: string): string {
  return dir ? `*${label} @ ${dir}*` : `*${label}*`;
}

export interface VirtualParts {
  /** The title without the `*` (for example `search: foo`). */
  label: string;
  /** The origin directory (undefined if none). */
  dir?: string;
}

export function parseVirtualPath(path: string): VirtualParts {
  const inner = path.slice(1, -1);
  const at = inner.lastIndexOf(" @ /");
  return at < 0 ? { label: inner } : { label: inner.slice(0, at), dir: inner.slice(at + 3) };
}

/** From an identity, the basic name that can be shown as is (duplicates are not yet disambiguated). */
function baseName(path: string): string {
  if (!path.startsWith("*")) return basename(path);
  return `*${parseVirtualPath(path).label}*`;
}

/** The directory that serves as the basis for disambiguation (the parent for a file, the origin for a virtual buffer). null if none. */
function directoryOf(path: string): string | null {
  if (path.startsWith("*")) return parseVirtualPath(path).dir ?? null;
  return path.slice(0, Math.max(path.lastIndexOf("/"), 0)) || "/";
}

/** Takes `count` levels from the end of a directory (2 levels of `/a/b/c` is `b/c`). The host's directory is `~`. */
function suffix(dir: string, count: number, home: string): string {
  const abbreviated = abbreviateHome(dir, home);
  const parts = abbreviated.split("/").filter((p, i) => p !== "" || i === 0);
  if (count >= parts.length) return abbreviated === "/" ? "/" : abbreviated;
  return parts.slice(-count).join("/");
}

/**
 * Computes display names from the identities of all (open) buffers.
 * When several share the same basic name, the directory's trailing part is added down to the smallest level that tells them apart.
 * A virtual buffer with an origin gets the origin added even without a collision (`*search: foo*<docs>`).
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
      // Find the smallest level that does not overlap with the suffixes of other buffers with the same name
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
