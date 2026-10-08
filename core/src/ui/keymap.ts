import { createKeymap } from "../keys.ts";
import type { Keymap } from "../keys.ts";
import type { CommandName } from "./commands.ts";

/** 標準のキー割り当て。docs/interaction-model.md。利用者の設定での上書きは M3。 */
export const DEFAULT_BINDINGS: Readonly<Record<string, CommandName>> = {
  "C-x 2": "split-below",
  "C-x 3": "split-right",
  "C-x 0": "delete-window",
  "C-x 1": "delete-other-windows",
  "C-x o": "other-window",
  "C-x b": "switch-buffer",
  "C-x C-f": "find-file",
  "M-x": "execute-command",
  // Back / Forward は、編集における C-f/C-b が文字の流れを泳ぐのと同じく、参照の流れを泳ぐ操作
  "C-f": "forward",
  "C-b": "back",
  "s-]": "forward",
  "s-[": "back",
  "C-n": "scroll-line-down",
  "C-p": "scroll-line-up",
  "C-v": "scroll-page-down",
  "M-v": "scroll-page-up",
  TAB: "next-link",
  "S-TAB": "prev-link",
  RET: "follow-link",
  "C-c j": "goto-heading",
  "M-s g": "search-project",
  "M-g g": "goto-line",
  "C-g": "keyboard-quit",
};

export function defaultKeymap(): Keymap {
  return createKeymap(DEFAULT_BINDINGS);
}
