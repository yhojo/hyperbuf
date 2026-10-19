// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// ホストからのイベント(外部更新、外部からの「開く」要求、位置の問い合わせ)の受け口。

import type { OpenRequest } from "../host.ts";
import { currentEntry, jump, openBuffer, selectedWindow } from "../model.ts";
import type { Commands } from "./commands.ts";
import type { AppContext } from "./context.ts";
import { abbreviateHome } from "../paths.ts";
import { ensureBuffer, errorMessage } from "./navigation.ts";

export function wireHostEvents(ctx: AppContext, commands: Commands): void {
  const { host, model, views, echo, minibuffer } = ctx;

  // 表示中のファイルの変更・削除。変更なら読み直し(位置の維持は Views が行う)、削除なら残して知らせる
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
      // 読めない = 消えた(または、置換の途中)。バッファは残して、知らせる
      buf.missing = true;
      views.refresh();
      echo.message(`Cannot revert: ${abbreviateHome(path, host.home)} (${errorMessage(err)})`);
    }
  });

  // 確認待ちの要求の id。期限切れで取り消されたら、その確認だけを閉じる。
  // 取り消された確認は、利用者の「拒否」ではない(シェルは、期限切れとして、すでに応答している)
  let confirming: string | null = null;
  let timedOut: string | null = null;
  host.onOpenCancel?.((id) => {
    if (confirming !== id) return;
    timedOut = id;
    minibuffer.cancel();
    echo.message("Integration: request timed out");
  });

  // 外部(CLI・Emacs 連携)からの「開く」要求。docs/dev/integration-protocol.md
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
      // 警告パスのファイルは、ダイアログではなくミニバッファで確認する(docs/dev/file-access.md)。
      // 承認されたら、シェルが提案したパスが記憶される(永続化される)。
      const where = req.remember ? `Remember ${abbreviateHome(req.remember, host.home)} and ` : "";
      confirming = req.id ?? null;
      const answer = await minibuffer.prompt(
        `${where}open ${abbreviateHome(req.path, host.home)} (a warn path)? `,
        ["yes", "no"],
        { allowFree: false },
      );
      confirming = null;
      if (req.id && timedOut === req.id) {
        // 期限切れで閉じられた。応答も、メッセージ(request timed out)も、すでに出ている
        timedOut = null;
        host.log?.(`CONFIRM ${req.path} timed out`);
        return;
      }
      host.log?.(`CONFIRM ${req.path} answer=${answer}`);
      // 回答は、承認でも拒否でも、シェルに伝える(承認が受理されたときだけ、読めるようになる)
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

  // シェルから「エディタで編集」(右クリックメニュー)が選ばれた
  host.onEdit?.(() => {
    void Promise.resolve(commands["edit-in-editor"]()).then(() => views.refresh());
  });

  // いまの表示の問い合わせ(`get-view`)。編集位置(`get-location`)は、シェルが保持する
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

  // 準備ができた合図。これ以前に届いていた要求が、ここで渡される。
  host.ready?.();
}
