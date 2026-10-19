// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import { createKeymap } from "../keys.ts";
import type { Keymap } from "../keys.ts";
import { applyOverrides } from "../keybindings.ts";
import type { BindingsResult, Overrides } from "../keybindings.ts";
import { COMMAND_NAMES } from "./commands.ts";
import type { CommandName } from "./commands.ts";

/** Default key bindings. docs/dev/interaction-model.md. Overriding by user settings is M3. */
export const DEFAULT_BINDINGS: Readonly<Record<string, CommandName>> = {
  "C-x 2": "split-below",
  "C-x 3": "split-right",
  "C-x 0": "delete-window",
  "C-x 1": "delete-other-windows",
  "C-x o": "other-window",
  "C-x ^": "enlarge-window",
  "C-x -": "shrink-window-if-larger-than-buffer",
  "C-x }": "enlarge-window-horizontally",
  "C-x {": "shrink-window-horizontally",
  "C-x b": "switch-buffer",
  "C-x k": "kill-buffer",
  "C-x C-f": "find-file",
  "C-x p f": "project-find-file",
  "C-x p g": "project-find-regexp",
  "C-x p b": "project-switch-to-buffer",
  "C-x p k": "project-kill-buffers",
  "C-x x u": "toggle-follow-updates",
  "C-x 5 2": "make-frame",
  "C-x 5 0": "delete-frame",
  "C-x 5 o": "other-frame",
  "C-x 5 1": "delete-other-frames",
  "M-x": "execute-command",
  // Back / Forward navigate the flow of references, just as C-f/C-b move through the flow of characters in editing
  "C-f": "forward",
  "C-b": "back",
  // Start / end of the history (like C-a / C-e at line start / end)
  "C-a": "beginning-of-history",
  "C-e": "end-of-history",
  // Left / right arrow keys too (for people unfamiliar with Emacs)
  left: "back",
  right: "forward",
  "s-]": "forward",
  "s-[": "back",
  // outline-mode-style heading navigation (the C-c prefix is reserved for this)
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
  "M-=": "count-words",
  // Edit the location pointed at in the viewer in the editor (same as "Edit in Emacs" in the right-click menu)
  "C-c e": "edit-in-editor",
  "C-h b": "describe-bindings",
  "C-g": "keyboard-quit",
};

export function defaultKeymap(): Keymap {
  return createKeymap(DEFAULT_BINDINGS);
}

/** Layers the user's settings (`keybindings`) over the default bindings. Problematic settings are ignored and the reason is returned. */
export function resolveBindings(overrides: Overrides | undefined): BindingsResult {
  return applyOverrides(DEFAULT_BINDINGS, overrides ?? {}, new Set<string>(COMMAND_NAMES));
}
