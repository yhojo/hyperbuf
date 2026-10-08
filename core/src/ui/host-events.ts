// ホストからのイベント(外部更新、外部からの「開く」要求、位置の問い合わせ)の受け口。

import type { OpenRequest } from "../host.ts";
import { currentEntry, openBuffer, selectedWindow } from "../model.ts";
import type { AppContext } from "./context.ts";
import { errorMessage, openAt } from "./navigation.ts";

export function wireHostEvents(ctx: AppContext): void {
  const { host, model, views, echo, minibuffer } = ctx;

  // 外部更新: 開いている buffer だけ読み直す。位置の維持は Views が行う。
  host.onFileChanged(async (path) => {
    if (!model.buffers.has(path)) return;
    try {
      openBuffer(model, path, await host.readFile(path));
      views.refresh();
      echo.message(`外部更新を反映: ${path}`);
    } catch (err) {
      echo.message(`外部更新を反映できません: ${path} (${errorMessage(err)})`);
    }
  });

  // 確認待ちの要求の id。期限切れで取り消されたら、その確認だけを閉じる。
  let confirming: string | null = null;
  host.onOpenCancel?.((id) => {
    if (confirming !== id) return;
    minibuffer.cancel();
    echo.message("連携: 要求の期限が切れました");
  });

  // 外部(CLI・Emacs 連携)からの「開く」要求。docs/integration-protocol.md
  host.onOpen?.(async (req: OpenRequest) => {
    const respond = (result: unknown): void => {
      if (req.id) host.respond?.(req.id, result);
    };
    const fail = (code: string, message: string): void => {
      echo.message(`連携: ${message}`);
      host.log?.(`REJECTED ${code} ${message}`);
      respond({ ok: false, error: { code, message } });
    };
    if (req.error) return fail("bad-request", req.error);
    if (req.outside) {
      // プロジェクトの範囲外は、ダイアログではなくミニバッファで確認する(docs/integration-protocol.md §6)。
      // 承認されたら、シェルが提案したルートが、信頼するルートに加わる(永続化される)。
      const where = req.root ? `${req.root} を信頼して、` : "";
      confirming = req.id ?? null;
      const answer = await minibuffer.prompt(
        `${where}${req.path} を開きますか(プロジェクトの外です)? `,
        ["yes", "no"],
        { allowFree: false },
      );
      confirming = null;
      host.log?.(`OUTSIDE ${req.path} answer=${answer}`);
      // 回答は、承認でも拒否でも、シェルに伝える(承認が受理されたときだけ、読めるようになる)
      const granted = (await host.confirmOutside?.(req.id ?? "", answer === "yes")) ?? false;
      if (answer !== "yes" || !granted) {
        return fail("outside-project", "範囲外のため開きませんでした");
      }
    }
    const anchor = req.anchor ?? (req.line ? `line:${req.line}` : null);
    try {
      await openAt(ctx, req.path, anchor);
      views.refresh();
      echo.message(`連携で開きました: ${req.path}${anchor ? "#" + anchor : ""}`);
      respond({ ok: true, result: { path: req.path } });
    } catch (err) {
      fail("not-found", `開けません: ${req.path} (${errorMessage(err)})`);
    }
  });

  // 位置の問い合わせ(M6 で、選択から元の位置を求める実装に置き換える。今は現在位置を返す)
  host.onQuery?.(async (op) => {
    if (op !== "get-location") return null;
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
