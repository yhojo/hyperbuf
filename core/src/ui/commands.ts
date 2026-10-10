// コマンドの定義。キーマップ(keymap.ts)は、キー列 → コマンド名の対応だけを持つ。
// M-x は、ここの名前をそのまま候補にする。

import {
  back,
  currentEntry,
  deleteOthers,
  deleteWindow,
  forward,
  otherWindow,
  selectedWindow,
  split,
  visit,
} from "../model.ts";
import { isVirtualPath, killBuffer } from "../model.ts";
import {
  currentIndex,
  nextIndex,
  previousIndex,
  sameLevelBackward,
  sameLevelForward,
  upIndex,
} from "../outline.ts";
import { headingElements, headingsOf } from "./anchors.ts";
import type { AppContext } from "./context.ts";
import { renderBindingsHelp } from "../help.ts";
import { openBuffer } from "../model.ts";
import { startIsearch } from "./isearch-dom.ts";
import { locateFromDom } from "./locate-dom.ts";
import { ensureBuffer, errorMessage, follow, openAt } from "./navigation.ts";
import { abbreviateHome } from "../paths.ts";
import { bufferNames } from "./directory.ts";
import { promptFindFile, promptFindFileRecursive } from "./files.ts";
import { searchProject } from "./search.ts";

export const COMMAND_NAMES = [
  "split-below",
  "split-right",
  "delete-window",
  "delete-other-windows",
  "other-window",
  "back",
  "forward",
  "scroll-line-down",
  "scroll-line-up",
  "scroll-page-down",
  "scroll-page-up",
  "beginning-of-document",
  "end-of-document",
  "next-heading",
  "previous-heading",
  "up-heading",
  "forward-same-level",
  "backward-same-level",
  "next-link",
  "prev-link",
  "follow-link",
  "switch-buffer",
  "kill-buffer",
  "find-file",
  "project-find-file",
  "forget-remembered-path",
  "make-frame",
  "delete-frame",
  "other-frame",
  "delete-other-frames",
  "goto-heading",
  "goto-line",
  "isearch-forward",
  "isearch-backward",
  "search-project",
  "edit-in-editor",
  "execute-command",
  "describe-bindings",
  "keyboard-quit",
] as const;

export type CommandName = (typeof COMMAND_NAMES)[number];

/** コマンドの説明(describe-bindings に出る)。全コマンドに必要(型で、漏れを検出する)。 */
export const COMMAND_DOCS: Readonly<Record<CommandName, string>> = {
  "split-below": "window を、上下に分割する(履歴は、複製される)",
  "split-right": "window を、左右に分割する(履歴は、複製される)",
  "delete-window": "選択中の window を閉じる",
  "delete-other-windows": "選択中の window だけを残す",
  "other-window": "次の window を選択する",
  back: "参照履歴を戻る",
  forward: "参照履歴を進む",
  "scroll-line-down": "1 行分、下へスクロールする",
  "scroll-line-up": "1 行分、上へスクロールする",
  "scroll-page-down": "1 画面分、下へスクロールする",
  "scroll-page-up": "1 画面分、上へスクロールする",
  "beginning-of-document": "文書の先頭へ",
  "end-of-document": "文書の末尾へ",
  "next-heading": "次の見出しへ(参照履歴には積まない)",
  "previous-heading": "前の見出しへ(節の途中なら、その節の見出しへ)",
  "up-heading": "上のレベルの見出しへ",
  "forward-same-level": "同じレベルの、次の見出しへ(親をまたがない)",
  "backward-same-level": "同じレベルの、前の見出しへ(親をまたがない)",
  "next-link": "次のリンクを選ぶ",
  "prev-link": "前のリンクを選ぶ",
  "follow-link": "選んでいるリンクをたどる",
  "switch-buffer": "開いている buffer を、最近使った順の候補から選んで表示する",
  "kill-buffer": "buffer を閉じる(どの window の履歴からも、その参照を取り除く)",
  "find-file":
    "ファイルを開く(基準のディレクトリから始まるパス補完。ディレクトリは RET で入る。~/・../・絶対パスも可)",
  "project-find-file":
    "基準のディレクトリ以下の Markdown を、再帰で一覧にして絞り込み、開く(../・~/・絶対パスで基準を変えられる)",
  "forget-remembered-path":
    "警告パスの下で、承認して記憶した場所を、選んで取り消す(次から、また確認される)",
  "make-frame": "新しいフレーム(macOS のウィンドウ)を作る。空いている最小の番号(Cmd-1〜)になる",
  "delete-frame": "このフレームを閉じる(最後の 1 つなら、アプリを終了する)",
  "other-frame": "次のフレームへ移る",
  "delete-other-frames": "このフレームだけを残して、ほかのフレームを閉じる",
  "goto-heading": "見出しを選んで、そこへ移動する",
  "goto-line": "元の Markdown の行番号を指定して、そこへ移動する",
  "isearch-forward":
    "文書内を、インクリメンタルに検索する(C-s で次、C-r で前、RET で確定、C-g で取消)",
  "isearch-backward": "文書内を、後ろ向きにインクリメンタル検索する",
  "search-project": "基準のディレクトリ以下を全文検索して、結果を仮想 buffer に出す",
  "edit-in-editor": "指した場所(選択・右クリック・画面の上端)を、エディタで編集するために記録する",
  "execute-command": "コマンドを、名前を選んで実行する",
  "describe-bindings": "キー割り当ての一覧を出す(設定の問題も)",
  "keyboard-quit": "入力途中のキーを取り消す",
};
export type Command = () => unknown;
export type Commands = Record<CommandName, Command>;

const LINE_PX = 48;

export function createCommands(ctx: AppContext): Commands {
  const { model, views, echo, minibuffer, host } = ctx;
  const sel = () => selectedWindow(model);

  /** 見出しの一覧から、移動先を求めて、そこへスクロールする。 */
  const moveToHeading = (
    pick: (tops: number[], levels: number[]) => number | null,
    none: string,
  ): void => {
    const headings = headingElements(views.selected().content);
    const index = pick(
      headings.map((h) => h.top),
      headings.map((h) => h.level),
    );
    const target = index === null ? undefined : headings[index];
    if (target) views.scrollTo(target.top);
    else echo.message(none);
  };

  /** 開いているバッファを、名前(uniquify 済み)の候補から選ぶ。候補は、最近使った順。 */
  const pickBuffer = async (label: string, history?: string): Promise<string | null> => {
    const names = bufferNames(ctx);
    const byName = new Map<string, string>();
    for (const path of model.mru) byName.set(names.get(path) ?? path, path);
    const picked = await minibuffer.prompt(label, [...byName.keys()], {
      allowFree: false,
      history,
    });
    return picked === null ? null : (byName.get(picked) ?? null);
  };

  /** 入力欄で選んだファイル(絶対パス)を開く。 */
  const openPicked = async (picking: Promise<string | null>): Promise<void> => {
    const path = await picking;
    if (!path) return;
    try {
      await openAt(ctx, path);
    } catch (err) {
      echo.message(`開けません: ${path} (${errorMessage(err)})`);
    }
  };

  const commands: Commands = {
    "split-below": () => split(model, "col"),
    "split-right": () => split(model, "row"),
    "delete-window": () => deleteWindow(model) || echo.message("これが唯一の window です"),
    "delete-other-windows": () => deleteOthers(model),
    "other-window": () => otherWindow(model),
    back: () => back(model, sel()) || echo.message("これより前の履歴はありません"),
    forward: () => forward(model, sel()) || echo.message("これより先の履歴はありません"),
    "scroll-line-down": () => views.scrollBy(LINE_PX),
    "scroll-line-up": () => views.scrollBy(-LINE_PX),
    "scroll-page-down": () => views.scrollBy(views.pageHeight() * 0.9),
    "scroll-page-up": () => views.scrollBy(-views.pageHeight() * 0.9),
    "beginning-of-document": () => views.scrollTo(0),
    "end-of-document": () => views.scrollTo(views.scrollHeight()),
    // outline-mode 風の見出し移動。文書内の移動なので、参照履歴には積まない
    "next-heading": () =>
      moveToHeading(
        (tops) => nextIndex(tops, views.scrollTop()),
        "これより後ろに見出しはありません",
      ),
    "previous-heading": () =>
      moveToHeading(
        (tops) => previousIndex(tops, views.scrollTop()),
        "これより前に見出しはありません",
      ),
    "up-heading": () =>
      moveToHeading(
        (tops, levels) => upIndex(levels, currentIndex(tops, views.scrollTop())),
        "上のレベルの見出しはありません",
      ),
    "forward-same-level": () =>
      moveToHeading(
        (tops, levels) => sameLevelForward(levels, currentIndex(tops, views.scrollTop())),
        "同じレベルの、次の見出しはありません",
      ),
    "backward-same-level": () =>
      moveToHeading(
        (tops, levels) => sameLevelBackward(levels, currentIndex(tops, views.scrollTop())),
        "同じレベルの、前の見出しはありません",
      ),
    "next-link": () => views.moveLink(1),
    "prev-link": () => views.moveLink(-1),
    "follow-link": async () => {
      const href = views.focusedHref();
      if (href !== null) await follow(ctx, sel(), href);
    },
    "switch-buffer": async () => {
      const path = await pickBuffer("Switch to buffer: ", "switch-buffer");
      if (path) visit(model, sel(), path);
    },
    "kill-buffer": async () => {
      const entry = currentEntry(sel());
      const names = bufferNames(ctx);
      const path = await pickBuffer(`Kill buffer (${names.get(entry?.path ?? "") ?? ""}): `);
      const target = path ?? entry?.path;
      if (path === null || !target || !model.buffers.has(target)) return;
      const empty = killBuffer(model, target);
      // 履歴が空になった window には、別の buffer(最近使ったもの)を表示する。なければ、空のまま
      for (const win of empty) {
        const next = model.mru[0];
        if (!next) continue;
        await ensureBuffer(ctx, next);
        visit(model, win, next);
      }
      echo.message(`buffer を閉じました: ${names.get(target) ?? target}`);
    },
    "find-file": () => openPicked(promptFindFile(ctx)),
    "forget-remembered-path": async () => {
      const remembered = (await host.listRemembered?.()) ?? [];
      if (!remembered.length) return void echo.message("記憶したパスはありません");
      const shown = new Map(remembered.map((p) => [abbreviateHome(p, host.home), p]));
      const picked = await minibuffer.prompt("Forget remembered path: ", [...shown.keys()], {
        allowFree: false,
      });
      const path = picked === null ? undefined : shown.get(picked);
      if (path === undefined) return;
      const ok = await host.forget?.(path);
      echo.message(ok ? `取り消しました: ${picked}` : "取り消せませんでした");
    },
    "make-frame": () => host.frame?.("make"),
    "delete-frame": () => host.frame?.("delete"),
    "other-frame": () => host.frame?.("other"),
    "delete-other-frames": () => host.frame?.("delete-others"),
    "project-find-file": () => openPicked(promptFindFileRecursive(ctx)),
    "goto-heading": async () => {
      const entry = currentEntry(sel());
      if (!entry) return;
      const headings = headingsOf(views.selected().content);
      const items = headings.map((h) => `${"  ".repeat(h.level - 1)}${h.text}`);
      const picked = await minibuffer.prompt("Heading: ", items, { allowFree: false });
      const heading = picked === null ? undefined : headings[items.indexOf(picked)];
      if (heading) visit(model, sel(), entry.path, heading.id);
    },
    "goto-line": async () => {
      const entry = currentEntry(sel());
      const n = Number(await minibuffer.prompt("Goto line: "));
      if (entry && Number.isInteger(n) && n > 0) visit(model, sel(), entry.path, `line:${n}`);
    },
    // 文書内のインクリメンタル検索(Emacs の isearch)。プロジェクト全体の検索は、search-project(M-s g)
    "isearch-forward": () => startIsearch(ctx, 1),
    "isearch-backward": () => startIsearch(ctx, -1),
    "search-project": async () => {
      const query = await minibuffer.prompt("Search: ");
      if (query) await searchProject(ctx, query);
    },
    // ビューアで指した場所(選択・右クリック・いま読んでいる場所)を、元の位置にして、エディタ連携のために記録する
    "edit-in-editor": async () => {
      const entry = currentEntry(sel());
      const buf = entry && model.buffers.get(entry.path);
      if (!entry || !buf) return;
      if (!host.markLocation) {
        echo.message("このホストは、エディタへの連携に対応していません");
        return;
      }
      if (isVirtualPath(entry.path)) {
        echo.message("ファイルに対応しない文書(検索結果など)は、エディタで編集できません");
        return;
      }
      const location = locateFromDom({
        content: views.selected().content,
        path: entry.path,
        text: buf.text,
        version: buf.version,
        contextTarget: views.contextTarget(),
      });
      if (!location) {
        echo.message("指した場所を、元の位置にできませんでした");
        return;
      }
      const result = await host.markLocation(location);
      const note = location.precision === "block" ? "(位置が曖昧なため、ブロック全体です)" : "";
      echo.message(`${result.message}${note}`);
    },
    "execute-command": async () => {
      const name = await minibuffer.prompt("M-x ", COMMAND_NAMES, { allowFree: false });
      const command = COMMAND_NAMES.find((n) => n === name);
      if (command) await commands[command]();
    },
    // キー割り当ての一覧(仮想 buffer)。設定の問題も、ここに出る
    "describe-bindings": () => {
      const path = "*Help: keybindings*";
      openBuffer(
        model,
        path,
        renderBindingsHelp({
          docs: COMMAND_DOCS,
          bindings: ctx.bindings.bindings,
          problems: [...ctx.bindings.problems, ...ctx.problems],
        }),
      );
      visit(model, sel(), path);
    },
    "keyboard-quit": () => echo.message("Quit"),
  };
  return commands;
}
