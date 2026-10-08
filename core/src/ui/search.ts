// プロジェクト内の全文検索。結果は仮想 buffer(`*search: …*`)に Markdown として並べ、
// リンクで該当行(行アンカー)へ飛ぶ。仮想 buffer の考え方: docs/interaction-model.md §5b。

import { openBuffer, selectedWindow, visit } from "../model.ts";
import type { AppContext } from "./context.ts";

export async function searchProject(ctx: AppContext, query: string): Promise<void> {
  const { host, model, echo } = ctx;
  if (!host.search) {
    echo.message("このホストは全文検索に対応していません");
    return;
  }
  const t0 = performance.now();
  const res = await host.search(query, { limit: 500 });
  if (res.error) {
    echo.message(`検索に失敗: ${res.error}`);
    return;
  }
  const shown = res.truncated ? `(先頭 ${res.results.length} 件を表示)` : "";
  const lines = [`# 検索: ${query.replace(/[`#]/g, "")}`, "", `${res.total} 件${shown}`, ""];
  for (const r of res.results) {
    const snippet = r.text.trim().replace(/`/g, "'");
    const label = `${r.path.replace(/[[\]]/g, "")}:${r.line}`;
    lines.push(`- [${label}](${encodeURI(r.path)}#line:${r.line}) \`${snippet}\``);
  }
  const vpath = `*search: ${query}*`;
  openBuffer(model, vpath, lines.join("\n"));
  visit(model, selectedWindow(model), vpath);
  echo.message(`検索 ${res.total} 件 (${(performance.now() - t0).toFixed(0)}ms)`);
}
