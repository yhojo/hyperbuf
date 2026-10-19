// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Full-text search under a starting directory (`M-s g` is the base directory, `C-x p g` the project root). Results are listed as Markdown in a virtual buffer (`*search: …*`),
// and links jump to the matching line (line anchor). On virtual buffers: docs/dev/interaction-model.md §5.

import { openBuffer, selectedWindow, visit } from "../model.ts";
import { virtualPath } from "../names.ts";
import { abbreviateHome } from "../paths.ts";
import type { AppContext } from "./context.ts";
import { defaultDirectory } from "./directory.ts";

/** Path used as a Markdown link destination (`(` `)` `#` `?` are encoded too, so the destination is not broken). */
const linkPath = (path: string): string =>
  encodeURI(path).replace(/[()#?]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

export async function searchProject(
  ctx: AppContext,
  query: string,
  dir: string = defaultDirectory(ctx),
): Promise<void> {
  const { host, model, echo } = ctx;
  if (!host.search) {
    echo.message("Full-text search is not supported by this host");
    return;
  }
  const t0 = performance.now();
  const res = await host.search(dir, query, { limit: 500 });
  if (res.refused) {
    echo.message(`Not searching: ${res.refused}`);
    return;
  }
  if (res.error) {
    echo.message(`Search failed: ${res.error}`);
    return;
  }
  const shown = res.truncated ? `(showing first ${res.results.length})` : "";
  const where = abbreviateHome(dir, host.home);
  const lines = [
    `# Search: ${query.replace(/[`#]/g, "")}`,
    "",
    `${res.total} matches under ${where}${shown}`,
    "",
  ];
  for (const r of res.results) {
    const snippet = r.text.trim().replace(/`/g, "'");
    // Shown as a path relative to the starting point. The link is an absolute path
    const shownPath = r.path.startsWith(`${dir}/`) ? r.path.slice(dir.length + 1) : r.path;
    const label = `${shownPath.replace(/[[\]]/g, "")}:${r.line}`;
    lines.push(`- [${label}](${linkPath(r.path)}#line:${r.line}) \`${snippet}\``);
  }
  const vpath = virtualPath(`search: ${query}`, dir);
  openBuffer(model, vpath, lines.join("\n"));
  visit(model, selectedWindow(model), vpath);
  echo.message(`Search: ${res.total} matches (${(performance.now() - t0).toFixed(0)}ms)`);
}
