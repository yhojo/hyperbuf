// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 起点のディレクトリ以下の全文検索(`M-s g` は基準のディレクトリ、`C-x p g` はプロジェクト・ルート)。結果は仮想 buffer(`*search: …*`)に Markdown として並べ、
// リンクで該当行(行アンカー)へ飛ぶ。仮想 buffer の考え方: docs/interaction-model.md §5b。

import { openBuffer, selectedWindow, visit } from "../model.ts";
import { virtualPath } from "../names.ts";
import { abbreviateHome } from "../paths.ts";
import type { AppContext } from "./context.ts";
import { defaultDirectory } from "./directory.ts";

/** Markdown のリンクの宛先にするパス(`(` `)` `#` `?` もエンコードして、宛先を壊さない)。 */
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
    // 表示は、起点からの相対パス。リンクは、絶対パス
    const shownPath = r.path.startsWith(`${dir}/`) ? r.path.slice(dir.length + 1) : r.path;
    const label = `${shownPath.replace(/[[\]]/g, "")}:${r.line}`;
    lines.push(`- [${label}](${linkPath(r.path)}#line:${r.line}) \`${snippet}\``);
  }
  const vpath = virtualPath(`search: ${query}`, dir);
  openBuffer(model, vpath, lines.join("\n"));
  visit(model, selectedWindow(model), vpath);
  echo.message(`Search: ${res.total} matches (${(performance.now() - t0).toFixed(0)}ms)`);
}
