// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 基準のディレクトリ以下の全文検索。結果は仮想 buffer(`*search: …*`)に Markdown として並べ、
// リンクで該当行(行アンカー)へ飛ぶ。仮想 buffer の考え方: docs/interaction-model.md §5b。

import { openBuffer, selectedWindow, visit } from "../model.ts";
import { virtualPath } from "../names.ts";
import { abbreviateHome } from "../paths.ts";
import type { AppContext } from "./context.ts";
import { defaultDirectory } from "./directory.ts";

/** Markdown のリンクの宛先にするパス(`(` `)` `#` `?` もエンコードして、宛先を壊さない)。 */
const linkPath = (path: string): string =>
  encodeURI(path).replace(/[()#?]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

export async function searchProject(ctx: AppContext, query: string): Promise<void> {
  const { host, model, echo } = ctx;
  if (!host.search) {
    echo.message("このホストは全文検索に対応していません");
    return;
  }
  const t0 = performance.now();
  const dir = defaultDirectory(ctx);
  const res = await host.search(dir, query, { limit: 500 });
  if (res.refused) {
    echo.message(`検索しません: ${res.refused}`);
    return;
  }
  if (res.error) {
    echo.message(`検索に失敗: ${res.error}`);
    return;
  }
  const shown = res.truncated ? `(先頭 ${res.results.length} 件を表示)` : "";
  const where = abbreviateHome(dir, host.home);
  const lines = [
    `# 検索: ${query.replace(/[`#]/g, "")}`,
    "",
    `${where} 以下: ${res.total} 件${shown}`,
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
  echo.message(`検索 ${res.total} 件 (${(performance.now() - t0).toFixed(0)}ms)`);
}
