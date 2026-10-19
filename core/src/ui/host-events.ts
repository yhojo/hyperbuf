// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Entry point for events from the host (external updates, external "open" requests, position queries).

import type { OpenRequest } from "../host.ts";
import { currentEntry, jump, openBuffer, selectedWindow } from "../model.ts";
import type { Commands } from "./commands.ts";
import type { AppContext } from "./context.ts";
import { abbreviateHome } from "../paths.ts";
import { ensureBuffer, errorMessage } from "./navigation.ts";

export function wireHostEvents(ctx: AppContext, commands: Commands): void {
  const { host, model, views, echo, minibuffer } = ctx;

  // Change or deletion of a displayed file. On change, re-read (Views keeps the position); on deletion, keep the buffer and notify
  host.onFileChanged(async (path, state) => {
    const buf = model.buffers.get(path);
    if (!buf) return;
    if (state === "deleted") {
      buf.missing = true;
      views.refresh();
      return;
    }
    try {
      openBuffer(model, path, await host.readFile(path));
      views.refresh();
      echo.message(`Reverted: ${abbreviateHome(path, host.home)}`);
    } catch (err) {
      // Unreadable = gone (or in the middle of a replace). Keep the buffer and notify
      buf.missing = true;
      views.refresh();
      echo.message(`Cannot revert: ${abbreviateHome(path, host.home)} (${errorMessage(err)})`);
    }
  });

  // Id of the request awaiting confirmation. If it is cancelled by expiry, close only that confirmation.
  // A cancelled confirmation is not the user's "deny" (the shell has already responded with expiry)
  let confirming: string | null = null;
  let timedOut: string | null = null;
  host.onOpenCancel?.((id) => {
    if (confirming !== id) return;
    timedOut = id;
    minibuffer.cancel();
    echo.message("Integration: request timed out");
  });

  // "Open" request from outside (CLI / Emacs integration). docs/dev/integration-protocol.md
  host.onOpen?.(async (req: OpenRequest) => {
    const respond = (result: unknown): void => {
      if (req.id) host.respond?.(req.id, result);
    };
    const fail = (code: string, message: string): void => {
      echo.message(`Integration: ${message}`);
      host.log?.(`REJECTED ${code} ${message}`);
      respond({ ok: false, error: { code, message } });
    };
    if (req.error) return fail("bad-request", req.error);
    if (req.confirm) {
      // Files under a warn path are confirmed in the minibuffer, not a dialog (docs/dev/file-access.md).
      // When approved, the path the shell proposed is remembered (persisted).
      const where = req.remember ? `Remember ${abbreviateHome(req.remember, host.home)} and ` : "";
      confirming = req.id ?? null;
      const answer = await minibuffer.prompt(
        `${where}open ${abbreviateHome(req.path, host.home)} (a warn path)? `,
        ["yes", "no"],
        { allowFree: false },
      );
      confirming = null;
      if (req.id && timedOut === req.id) {
        // Closed by expiry. The response and the message (request timed out) have already been shown
        timedOut = null;
        host.log?.(`CONFIRM ${req.path} timed out`);
        return;
      }
      host.log?.(`CONFIRM ${req.path} answer=${answer}`);
      // Tell the shell the answer, whether approved or denied (the file becomes readable only when the approval is accepted)
      const granted = (await host.confirmOpen?.(req.id ?? "", answer === "yes")) ?? false;
      if (answer !== "yes" || !granted) {
        return fail("outside-project", "Not opened because it is a warn path");
      }
    }
    const anchor = req.anchor ?? (req.line ? `line:${req.line}` : null);
    try {
      await ensureBuffer(ctx, req.path);
      jump(model, selectedWindow(model), req.path, anchor);
      views.refresh();
      echo.message(
        `Opened by integration: ${abbreviateHome(req.path, host.home)}${anchor ? "#" + anchor : ""}`,
      );
      respond({ ok: true, result: { path: req.path } });
    } catch (err) {
      fail("not-found", `Cannot open: ${req.path} (${errorMessage(err)})`);
    }
  });

  // "Edit in editor" (right-click menu) was chosen from the shell
  host.onEdit?.(() => {
    void Promise.resolve(commands["edit-in-editor"]()).then(() => views.refresh());
  });

  // Query for the current view (`get-view`). The edit location (`get-location`) is held by the shell
  host.onQuery?.(async (op) => {
    if (op !== "get-view") return null;
    const win = selectedWindow(model);
    const entry = currentEntry(win);
    if (!entry) return null;
    return {
      path: entry.path,
      anchor: entry.anchor,
      scrollTop: Math.round(views.selected().content.scrollTop),
      history: `${win.index + 1}/${win.history.length}`,
    };
  });

  // Ready signal. Requests that arrived before this are handed over here.
  host.ready?.();
}
