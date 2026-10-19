// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// コマンドの定義。キーマップ(keymap.ts)は、キー列 → コマンド名の対応だけを持つ。
// M-x は、ここの名前をそのまま候補にする。

import {
  back,
  backToStart,
  currentEntry,
  deleteOthers,
  deleteWindow,
  forward,
  forwardToEnd,
  otherWindow,
  selectedWindow,
  split,
  visit,
} from "../model.ts";
import { isVirtualPath, killBuffer, type Win } from "../model.ts";
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
import { countText, formatCounts } from "../count.ts";
import { displayedText } from "./count-dom.ts";
import { locateFromDom } from "./locate-dom.ts";
import { ensureBuffer, errorMessage, follow, openAt } from "./navigation.ts";
import { abbreviateHome } from "../paths.ts";
import { bufferNames, currentProjectRoot } from "./directory.ts";
import { projectBuffers } from "./project.ts";
import { displayDir, promptFindFile, promptFindFileRecursive } from "./files.ts";
import { searchProject } from "./search.ts";

export const COMMAND_NAMES = [
  "split-below",
  "split-right",
  "delete-window",
  "delete-other-windows",
  "other-window",
  "enlarge-window",
  "shrink-window-if-larger-than-buffer",
  "enlarge-window-horizontally",
  "shrink-window-horizontally",
  "back",
  "forward",
  "beginning-of-history",
  "end-of-history",
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
  "project-switch-to-buffer",
  "project-kill-buffers",
  "find-file",
  "project-find-file",
  "forget-remembered-path",
  "forget-remembered-site",
  "toggle-follow-updates",
  "make-frame",
  "delete-frame",
  "other-frame",
  "delete-other-frames",
  "goto-heading",
  "goto-line",
  "count-words",
  "isearch-forward",
  "isearch-backward",
  "search-project",
  "project-find-regexp",
  "edit-in-editor",
  "execute-command",
  "describe-bindings",
  "keyboard-quit",
] as const;

export type CommandName = (typeof COMMAND_NAMES)[number];

/** コマンドの説明(describe-bindings に出る)。全コマンドに必要(型で、漏れを検出する)。 */
export const COMMAND_DOCS: Readonly<Record<CommandName, string>> = {
  "split-below": "Split the window above and below (history is copied)",
  "split-right": "Split the window side by side (history is copied)",
  "delete-window": "Delete the selected window",
  "delete-other-windows": "Make the selected window fill the frame",
  "other-window": "Select the next window",
  "enlarge-window": "Make the selected window taller (its neighbour shrinks)",
  "shrink-window-if-larger-than-buffer":
    "Shrink the selected window to fit its document if it is taller than the document",
  "enlarge-window-horizontally": "Make the selected window wider (its neighbour shrinks)",
  "shrink-window-horizontally": "Make the selected window narrower (its neighbour grows)",
  back: "Go back in reference history",
  forward: "Go forward in reference history",
  "beginning-of-history": "Go to the first entry of the reference history",
  "end-of-history": "Go to the last entry of the reference history",
  "scroll-line-down": "Scroll down one line",
  "scroll-line-up": "Scroll up one line",
  "scroll-page-down": "Scroll down one screen",
  "scroll-page-up": "Scroll up one screen",
  "beginning-of-document": "Go to the beginning of the document",
  "end-of-document": "Go to the end of the document",
  "next-heading": "Go to the next heading (not pushed onto reference history)",
  "previous-heading":
    "Go to the previous heading (the current section's heading if in the middle of one)",
  "up-heading": "Go up to the parent heading",
  "forward-same-level": "Go to the next heading at the same level (does not cross parents)",
  "backward-same-level": "Go to the previous heading at the same level (does not cross parents)",
  "next-link": "Select the next link",
  "prev-link": "Select the previous link",
  "follow-link": "Follow the selected link",
  "switch-buffer": "Switch to a buffer chosen from the open buffers (most recently used first)",
  "kill-buffer": "Kill a buffer (its references are removed from every window's history)",
  "project-switch-to-buffer":
    "Switch to a buffer of the current project (same project root; most recently used first)",
  "project-kill-buffers":
    "Kill all buffers of the current project (same project root) after confirming",
  "find-file":
    "Visit a file (path completion starting at the base directory; RET enters a directory; ~/, ../ and absolute paths also work)",
  "project-find-file":
    "Visit a Markdown file from a recursive list under the base directory (../, ~/ and absolute paths change the base)",
  "forget-remembered-path":
    "Forget a location approved and remembered under a warn path (it will be confirmed again)",
  "forget-remembered-site":
    'Forget a site remembered with "always" for opening in the browser (it will be confirmed again)',
  "toggle-follow-updates":
    "Toggle jumping to the first changed place when a file is updated externally (off by default; [Follow] in the mode line)",
  "make-frame":
    "Make a new frame (a macOS window), numbered with the smallest free number (Cmd-1...)",
  "delete-frame": "Delete this frame (quits the app if it is the last one)",
  "other-frame": "Select the next frame",
  "delete-other-frames": "Delete all other frames",
  "goto-heading": "Go to a heading chosen from a list",
  "goto-line": "Go to a line number of the source Markdown",
  "count-words":
    "Count the lines, words and characters of the selected text (or of the whole document) as displayed",
  "isearch-forward":
    "Search the document incrementally (C-s next, C-r previous, RET accept, C-g cancel)",
  "isearch-backward": "Search the document incrementally, backward",
  "project-find-regexp":
    "Search all files under the project root (the nearest ancestor with .git/.hg/…, or the base directory) and show the results in a virtual buffer (plain text, case-insensitive for ASCII; .gitignore is not read)",
  "search-project":
    "Search all files under the base directory and show the results in a virtual buffer",
  "edit-in-editor":
    "Record the location at point (selection, right-click or top of the screen) for editing in the editor",
  "execute-command": "Execute a command chosen by name",
  "describe-bindings": "Show the list of key bindings (and configuration problems)",
  "keyboard-quit": "Cancel the key sequence in progress",
};
export type Command = () => unknown;
export type Commands = Record<CommandName, Command>;

const LINE_PX = 48;
/** window の大きさを変える 1 回分(`enlarge-window` など。Emacs の 1 行・1 桁に当たる、ピクセル数)。 */
const RESIZE_V_PX = 48;
const RESIZE_H_PX = 80;
const NO_SPLIT = (axis: string): string => `No ${axis} split to resize`;

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
  const pickBuffer = async (
    label: string,
    history?: string,
    candidates: readonly string[] = model.mru,
  ): Promise<string | null> => {
    const names = bufferNames(ctx);
    const byName = new Map<string, string>();
    for (const path of candidates) byName.set(names.get(path) ?? path, path);
    const picked = await minibuffer.prompt(label, [...byName.keys()], {
      allowFree: false,
      history,
    });
    return picked === null ? null : (byName.get(picked) ?? null);
  };

  /** buffer を閉じる。履歴が空になった window には、別の buffer(最近使ったもの)を表示する。なければ、空のまま。 */
  const killBuffers = async (paths: readonly string[]): Promise<void> => {
    const empty = new Map<number, Win>();
    for (const path of paths) {
      if (!model.buffers.has(path)) continue;
      for (const win of killBuffer(model, path)) empty.set(win.id, win);
    }
    for (const win of empty.values()) {
      const next = model.mru[0];
      if (!next) continue;
      await ensureBuffer(ctx, next);
      visit(model, win, next);
    }
  };

  /** 入力欄で選んだファイル(絶対パス)を開く。 */
  const openPicked = async (picking: Promise<string | null>): Promise<void> => {
    const path = await picking;
    if (!path) return;
    try {
      await openAt(ctx, path);
    } catch (err) {
      echo.message(`Cannot open: ${path} (${errorMessage(err)})`);
    }
  };

  const commands: Commands = {
    "split-below": () => split(model, "col"),
    "split-right": () => split(model, "row"),
    "delete-window": () => deleteWindow(model) || echo.message("Attempt to delete sole window"),
    "delete-other-windows": () => deleteOthers(model),
    "other-window": () => otherWindow(model),
    "enlarge-window": () =>
      views.resizeSelected("col", RESIZE_V_PX) || echo.message(NO_SPLIT("vertical")),
    "shrink-window-if-larger-than-buffer": () => {
      const result = views.shrinkToFit();
      if (result === "sole") echo.message("Attempt to delete sole window");
      else if (result === "fits") echo.message("Window is not larger than the document");
    },
    "enlarge-window-horizontally": () =>
      views.resizeSelected("row", RESIZE_H_PX) || echo.message(NO_SPLIT("horizontal")),
    "shrink-window-horizontally": () =>
      views.resizeSelected("row", -RESIZE_H_PX) || echo.message(NO_SPLIT("horizontal")),
    back: () => back(model, sel()) || echo.message("Beginning of history"),
    forward: () => forward(model, sel()) || echo.message("No further history"),
    "beginning-of-history": () => backToStart(model, sel()) || echo.message("Beginning of history"),
    "end-of-history": () => forwardToEnd(model, sel()) || echo.message("End of history"),
    "scroll-line-down": () => views.scrollBy(LINE_PX),
    "scroll-line-up": () => views.scrollBy(-LINE_PX),
    "scroll-page-down": () => views.scrollBy(views.pageHeight() * 0.9),
    "scroll-page-up": () => views.scrollBy(-views.pageHeight() * 0.9),
    "beginning-of-document": () => views.scrollTo(0),
    "end-of-document": () => views.scrollTo(views.scrollHeight()),
    // outline-mode 風の見出し移動。文書内の移動なので、参照履歴には積まない
    "next-heading": () =>
      moveToHeading((tops) => nextIndex(tops, views.scrollTop()), "No following heading"),
    "previous-heading": () =>
      moveToHeading((tops) => previousIndex(tops, views.scrollTop()), "No previous heading"),
    "up-heading": () =>
      moveToHeading(
        (tops, levels) => upIndex(levels, currentIndex(tops, views.scrollTop())),
        "No parent heading",
      ),
    "forward-same-level": () =>
      moveToHeading(
        (tops, levels) => sameLevelForward(levels, currentIndex(tops, views.scrollTop())),
        "No next heading at this level",
      ),
    "backward-same-level": () =>
      moveToHeading(
        (tops, levels) => sameLevelBackward(levels, currentIndex(tops, views.scrollTop())),
        "No previous heading at this level",
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
      await killBuffers([target]);
      echo.message(`Killed buffer: ${names.get(target) ?? target}`);
    },
    "project-switch-to-buffer": async () => {
      const { root, paths } = await projectBuffers(ctx);
      if (!paths.length) return void echo.message("No buffers in this project");
      const path = await pickBuffer(
        `Switch to buffer in ${displayDir(root, host.home)}: `,
        "switch-buffer",
        paths,
      );
      if (path) visit(model, sel(), path);
    },
    "project-kill-buffers": async () => {
      const { root, paths } = await projectBuffers(ctx);
      if (!paths.length) return void echo.message("No buffers in this project");
      const where = abbreviateHome(root, host.home);
      const answer = await minibuffer.prompt(
        `Kill ${paths.length} buffer${paths.length === 1 ? "" : "s"} in ${where}? `,
        ["yes", "no"],
        { allowFree: false },
      );
      if (answer !== "yes") return;
      await killBuffers(paths);
      echo.message(`Killed ${paths.length} buffer${paths.length === 1 ? "" : "s"} in ${where}`);
    },
    "find-file": () => openPicked(promptFindFile(ctx)),
    "forget-remembered-path": async () => {
      const remembered = (await host.listRemembered?.()) ?? [];
      if (!remembered.length) return void echo.message("No remembered paths");
      const shown = new Map(remembered.map((p) => [abbreviateHome(p, host.home), p]));
      const picked = await minibuffer.prompt("Forget remembered path: ", [...shown.keys()], {
        allowFree: false,
      });
      const path = picked === null ? undefined : shown.get(picked);
      if (path === undefined) return;
      const ok = await host.forget?.(path);
      echo.message(ok ? `Forgot: ${picked}` : "Could not forget");
    },
    "forget-remembered-site": async () => {
      const sites = (await host.listRememberedSites?.()) ?? [];
      if (!sites.length) return void echo.message("No remembered sites");
      const picked = await minibuffer.prompt("Forget remembered site: ", sites, {
        allowFree: false,
      });
      if (picked === null) return;
      const ok = await host.forgetSite?.(picked);
      echo.message(ok ? `Forgot: ${picked}` : "Could not forget");
    },
    "toggle-follow-updates": () => {
      views.followUpdates = !views.followUpdates;
      views.refresh();
      echo.message(
        views.followUpdates
          ? "Follow updates: on (jumps to the first changed place on external updates)"
          : "Follow updates: off (keeps the reading position)",
      );
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
    "count-words": () => {
      const shown = displayedText(views.selected().content);
      if (!shown) return echo.message("No document");
      echo.message(formatCounts(shown.scope, countText(shown.text)));
    },
    "goto-line": async () => {
      const entry = currentEntry(sel());
      const n = Number(await minibuffer.prompt("Goto line: "));
      if (entry && Number.isInteger(n) && n > 0) visit(model, sel(), entry.path, `line:${n}`);
    },
    // 文書内のインクリメンタル検索(Emacs の isearch)。プロジェクト全体の検索は、search-project(M-s g)
    "isearch-forward": () => startIsearch(ctx, 1),
    "isearch-backward": () => startIsearch(ctx, -1),
    "project-find-regexp": async () => {
      const root = await currentProjectRoot(ctx);
      const query = await minibuffer.prompt(`Search in ${displayDir(root, host.home)}: `);
      if (query) await searchProject(ctx, query, root);
    },
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
        echo.message("Editor integration is not supported by this host");
        return;
      }
      if (isVirtualPath(entry.path)) {
        echo.message(
          "Documents without a file (e.g. search results) cannot be edited in the editor",
        );
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
        echo.message("Could not map the location to the source");
        return;
      }
      const result = await host.markLocation(location);
      const note =
        location.precision === "block" ? " (position is ambiguous; the whole block)" : "";
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
