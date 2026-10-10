import { createKeymap } from "../keys.ts";
import type { Keymap } from "../keys.ts";
import { applyOverrides } from "../keybindings.ts";
import type { BindingsResult, Overrides } from "../keybindings.ts";
import { COMMAND_NAMES } from "./commands.ts";
import type { CommandName } from "./commands.ts";

/** 標準のキー割り当て。docs/interaction-model.md。利用者の設定での上書きは M3。 */
export const DEFAULT_BINDINGS: Readonly<Record<string, CommandName>> = {
  "C-x 2": "split-below",
  "C-x 3": "split-right",
  "C-x 0": "delete-window",
  "C-x 1": "delete-other-windows",
  "C-x o": "other-window",
  "C-x b": "switch-buffer",
  "C-x k": "kill-buffer",
  "C-x C-f": "find-file",
  "C-x p f": "project-find-file",
  "M-x": "execute-command",
  // Back / Forward は、編集における C-f/C-b が文字の流れを泳ぐのと同じく、参照の流れを泳ぐ操作
  "C-f": "forward",
  "C-b": "back",
  "s-]": "forward",
  "s-[": "back",
  // outline-mode 風の見出し移動(C-c 系は、このために取ってある)
  "C-c C-n": "next-heading",
  "C-c C-p": "previous-heading",
  "C-c C-u": "up-heading",
  "C-c C-f": "forward-same-level",
  "C-c C-b": "backward-same-level",
  "M-<": "beginning-of-document",
  "M->": "end-of-document",
  SPC: "scroll-page-down",
  DEL: "scroll-page-up",
  "S-SPC": "scroll-page-up",
  "C-n": "scroll-line-down",
  "C-p": "scroll-line-up",
  "C-v": "scroll-page-down",
  "M-v": "scroll-page-up",
  TAB: "next-link",
  "S-TAB": "prev-link",
  RET: "follow-link",
  "C-c j": "goto-heading",
  "C-s": "isearch-forward",
  "C-r": "isearch-backward",
  "M-s g": "search-project",
  "M-g g": "goto-line",
  // ビューアで指した場所を、エディタで編集する(右クリックメニューの「Emacs で編集」と同じ)
  "C-c e": "edit-in-editor",
  "C-h b": "describe-bindings",
  "C-g": "keyboard-quit",
};

export function defaultKeymap(): Keymap {
  return createKeymap(DEFAULT_BINDINGS);
}

/** 標準の割り当てに、利用者の設定(`keybindings`)を重ねる。問題のある設定は、無視して、理由を返す。 */
export function resolveBindings(overrides: Overrides | undefined): BindingsResult {
  return applyOverrides(DEFAULT_BINDINGS, overrides ?? {}, new Set<string>(COMMAND_NAMES));
}
