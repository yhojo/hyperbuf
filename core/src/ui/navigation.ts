// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 文書を開く・リンクをたどる。buffer の読み込みと、参照履歴への記録をまとめる。

import { currentEntry, openBuffer, resolveLink, selectedWindow, visit } from "../model.ts";
import type { Win } from "../model.ts";
import { abbreviateHome } from "../paths.ts";
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

/**
 * リンクやリソースが指すファイルへのアクセスを確かめる(docs/project-model.md §5)。
 * 警告パスのファイルなら、ミニバッファで確認し、承認されたら、シェルに記憶させる。
 * @returns 開いてよいか
 */
export async function confirmAccess(ctx: AppContext, path: string): Promise<boolean> {
  const { host, minibuffer } = ctx;
  if (!host.checkAccess) return true;
  const [decision] = await host.checkAccess([path]);
  if (!decision || decision.access === "allow") return true;
  const answer = await minibuffer.prompt(
    `${abbreviateHome(path, host.home)} は警告パスです。開きますか? `,
    ["yes", "no"],
    { allowFree: false },
  );
  if (answer !== "yes") return false;
  return (await host.allow?.(decision.remember)) ?? false;
}

/**
 * 外部の URL(`https://…` など)を、既定のブラウザで開く。文書の中身はアプリの中で開かない(local first)ので、
 * ブラウザに渡す。確認の方針は、シェルが判定する(`trustedUrls` → 記憶したサイト → 確認)。
 */
export async function openExternalLink(ctx: AppContext, href: string): Promise<void> {
  const { host, echo, minibuffer } = ctx;
  if (!host.checkUrl || !host.openExternal) {
    echo.message(`外部リンクは開きません: ${href}`);
    return;
  }
  const decision = await host.checkUrl(href);
  if (decision.action === "deny") {
    echo.message(`開きません: ${decision.reason}: ${shorten(href)}`);
    return;
  }
  if (decision.action === "confirm") {
    // URL 全体を見せる(ホストの偽装に気づけるよう、オリジンも添える)
    const answer = await minibuffer.prompt(
      `ブラウザで開きますか? ${shorten(href, 160)}${decision.origin ? ` [${decision.origin}] (always: このサイトを常に許可)` : ""} `,
      decision.origin ? ["yes", "no", "always"] : ["yes", "no"],
      { allowFree: false },
    );
    if (answer !== "yes" && answer !== "always") {
      echo.message(`開きませんでした: ${shorten(href)}`);
      return;
    }
    if (answer === "always" && !(await host.rememberSite?.(href))) {
      echo.message("このサイトを記憶できませんでした(今回は開きます)");
    }
  }
  const opened = await host.openExternal(href);
  echo.message(
    opened ? `ブラウザで開きました: ${shorten(href)}` : `開けませんでした: ${shorten(href)}`,
  );
}

function shorten(text: string, max = 100): string {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

/** リンクをたどる。外部 URL は、ブラウザで開く(確認の方針はシェル)。警告パスのファイルは、確認する。 */
export async function follow(ctx: AppContext, win: Win, href: string): Promise<void> {
  const entry = currentEntry(win);
  if (!entry) return;
  const target = resolveLink(entry.path, href);
  if (!target) {
    await openExternalLink(ctx, href);
    return;
  }
  if (!ctx.model.buffers.has(target.path) && !(await confirmAccess(ctx, target.path))) {
    ctx.echo.message(`開きませんでした: ${abbreviateHome(target.path, ctx.host.home)}`);
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
