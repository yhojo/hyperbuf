// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Opening documents and following links. Combines buffer loading with recording in the reference history.

import { currentEntry, openBuffer, resolveLink, selectedWindow, visit } from "../model.ts";
import type { Win } from "../model.ts";
import { abbreviateHome } from "../paths.ts";
import type { AppContext } from "./context.ts";

/** If there is no buffer, read it from the host and create it. */
export async function ensureBuffer(ctx: AppContext, path: string): Promise<void> {
  if (ctx.model.buffers.has(path)) return;
  openBuffer(ctx.model, path, await ctx.host.readFile(path));
}

/** Opens a document in the selected window (pushed onto the reference history). Failures are handled by the caller. */
export async function openAt(
  ctx: AppContext,
  path: string,
  anchor: string | null = null,
): Promise<void> {
  await ensureBuffer(ctx, path);
  visit(ctx.model, selectedWindow(ctx.model), path, anchor);
}

/**
 * Checks access to the file a link or resource points to (docs/dev/file-access.md).
 * For a file under a warn path, confirm in the minibuffer and, if approved, have the shell remember it.
 * @returns whether it may be opened
 */
export async function confirmAccess(ctx: AppContext, path: string): Promise<boolean> {
  const { host, minibuffer } = ctx;
  if (!host.checkAccess) return true;
  const [decision] = await host.checkAccess([path]);
  if (!decision || decision.access === "allow") return true;
  const answer = await minibuffer.prompt(
    `${abbreviateHome(path, host.home)} is a warn path. Open it? `,
    ["yes", "no"],
    { allowFree: false },
  );
  if (answer !== "yes") return false;
  return (await host.allow?.(decision.remember)) ?? false;
}

/**
 * Opens an external URL (`https://…` etc.) in the default browser. Document contents are not opened inside the app (local first),
 * so they are passed to the browser. The shell decides the confirmation policy (`trustedUrls` -> remembered sites -> confirm).
 */
export async function openExternalLink(ctx: AppContext, href: string): Promise<void> {
  const { host, echo, minibuffer } = ctx;
  if (!host.checkUrl || !host.openExternal) {
    echo.message(`External links are not opened: ${href}`);
    return;
  }
  const decision = await host.checkUrl(href);
  if (decision.action === "deny") {
    echo.message(`Not opening: ${decision.reason}: ${shorten(href)}`);
    return;
  }
  if (decision.action === "confirm") {
    // Show the whole URL (with the origin attached so that host spoofing can be noticed)
    const answer = await minibuffer.prompt(
      `Open in browser? ${shorten(href, 160)}${decision.origin ? ` [${decision.origin}] (always: allow this site from now on)` : ""} `,
      decision.origin ? ["yes", "no", "always"] : ["yes", "no"],
      { allowFree: false },
    );
    if (answer !== "yes" && answer !== "always") {
      echo.message(`Not opened: ${shorten(href)}`);
      return;
    }
    if (answer === "always" && !(await host.rememberSite?.(href))) {
      echo.message("Could not remember this site (opening it this time)");
    }
  }
  const opened = await host.openExternal(href);
  echo.message(opened ? `Opened in browser: ${shorten(href)}` : `Could not open: ${shorten(href)}`);
}

function shorten(text: string, max = 100): string {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
}

/** Follows a link. External URLs open in the browser (confirmation policy is the shell's). Files under a warn path are confirmed. */
export async function follow(ctx: AppContext, win: Win, href: string): Promise<void> {
  const entry = currentEntry(win);
  if (!entry) return;
  const target = resolveLink(entry.path, href);
  if (!target) {
    await openExternalLink(ctx, href);
    return;
  }
  if (!ctx.model.buffers.has(target.path) && !(await confirmAccess(ctx, target.path))) {
    ctx.echo.message(`Not opened: ${abbreviateHome(target.path, ctx.host.home)}`);
    return;
  }
  try {
    await ensureBuffer(ctx, target.path);
  } catch (err) {
    ctx.echo.message(`Cannot open: ${target.path} (${errorMessage(err)})`);
    return;
  }
  visit(ctx.model, win, target.path, target.anchor);
}

export function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
