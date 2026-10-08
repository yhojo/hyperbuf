// 文書を開く・リンクをたどる。buffer の読み込みと、参照履歴への記録をまとめる。

import { currentEntry, openBuffer, resolveLink, selectedWindow, visit } from "../model.ts";
import type { Win } from "../model.ts";
import type { AppContext } from "./context.ts";

/** buffer がなければ、ホストから読んで作る。 */
export async function ensureBuffer(ctx: AppContext, path: string): Promise<void> {
  if (ctx.model.buffers.has(path)) return;
  openBuffer(ctx.model, path, await ctx.host.readFile(path));
}

/** 選択中の window で、文書を開く(参照履歴に積まれる)。失敗は呼び出し側で扱う。 */
export async function openAt(
  ctx: AppContext,
  path: string,
  anchor: string | null = null,
): Promise<void> {
  await ensureBuffer(ctx, path);
  visit(ctx.model, selectedWindow(ctx.model), path, anchor);
}

/** リンクをたどる。外部 URL は開かない(local first)。 */
export async function follow(ctx: AppContext, win: Win, href: string): Promise<void> {
  const entry = currentEntry(win);
  if (!entry) return;
  const target = resolveLink(entry.path, href);
  if (!target) {
    ctx.echo.message(`外部リンクは開きません: ${href}`);
    return;
  }
  try {
    await ensureBuffer(ctx, target.path);
  } catch (err) {
    ctx.echo.message(`開けません: ${target.path} (${errorMessage(err)})`);
    return;
  }
  visit(ctx.model, win, target.path, target.anchor);
}

export function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
