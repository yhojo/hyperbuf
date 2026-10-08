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
import { isVirtualPath } from "../model.ts";
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
import { startIsearch } from "./isearch-dom.ts";
import { locateFromDom } from "./locate-dom.ts";
import { errorMessage, follow, openAt } from "./navigation.ts";
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
  "find-file",
  "goto-heading",
  "goto-line",
  "isearch-forward",
  "isearch-backward",
  "search-project",
  "edit-in-editor",
  "execute-command",
  "keyboard-quit",
] as const;

export type CommandName = (typeof COMMAND_NAMES)[number];
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
      const path = await minibuffer.prompt("Switch to buffer: ", model.mru, { allowFree: false });
      if (path) visit(model, sel(), path);
    },
    "find-file": async () => {
      const path = await minibuffer.prompt("Find file: ", await host.listFiles());
      if (!path) return;
      try {
        await openAt(ctx, path);
      } catch (err) {
        echo.message(`開けません: ${path} (${errorMessage(err)})`);
      }
    },
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
      const query = await minibuffer.prompt("Search project: ");
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
    "keyboard-quit": () => echo.message("Quit"),
  };
  return commands;
}
