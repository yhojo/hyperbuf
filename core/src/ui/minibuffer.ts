// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Minibuffer. Search, candidate selection and confirmation happen here at the bottom of the screen, not in dialogs.
// While the input field has focus, C-f/C-b/C-a/C-e etc. are left to the WebView's default character movement
// (only confirm / cancel / candidate-selection keys are handled; same behavior as the Emacs minibuffer).
//
// Two modes of use:
//  - prompt: input with candidates (fuzzy narrowing). M-p / M-n walk the history of inputs of the same kind
//  - live:   process on every input (incremental search). Special keys (C-s, C-r, etc.) are handled by the caller

import { fuzzyFilter, matchRanges } from "../fuzzy.ts";
import { keyName } from "../keys.ts";
import { byId } from "./dom.ts";

/** Number of candidates displayed. */
export const VISIBLE_CANDIDATES = 10;
/** Number of input history entries kept per kind. */
const HISTORY_LIMIT = 50;

/** Candidates derived from the input. Fuzzy-narrowed by `fragment`; TAB replaces the input with `prefix + candidate`. */
export interface PromptSource {
  items: readonly string[];
  /** Part of the input placed before the candidate (such as a directory path). */
  prefix: string;
  /** Part of the input that narrows the candidates. */
  fragment: string;
}

/** Result of `RET`: `done` confirms, `text` continues with the input field set to that string (enters a directory), null does nothing. */
export type PromptChoice = { done: string } | { text: string } | null;

export interface PromptOptions {
  /** Whether free input that is not among the candidates is accepted. Default true. */
  allowFree?: boolean;
  /** Kind of input history (walked with M-p / M-n). If omitted, no history is used. */
  history?: string;
  /** Initial string of the input field (such as the base directory when opening a file). */
  initial?: string;
  /** Derive candidates on every input (if omitted, `candidates` is used). */
  source?: (text: string) => PromptSource | Promise<PromptSource>;
  /** Handling of `RET` (if omitted, the selected candidate, otherwise the input itself). */
  choose?: (picked: string | null, text: string, source: PromptSource) => PromptChoice;
}

export interface LiveHandlers {
  /** The input changed. */
  /** `composing`: whether the input is mid-conversion (before confirming) in Japanese input. */
  onInput(text: string, composing: boolean): void;
  /**
   * Special keys: those other than RET (confirm) and C-g / ESC (cancel) that the caller handles (C-s, C-r, etc.).
   * Return true if handled (stops the default behavior).
   */
  onKey(name: string): boolean;
}

export interface LiveSession {
  /** Changes the label at the left of the input field (status display). */
  setLabel(text: string): void;
  /** Changes the display at the right of the input field (match number / count, etc.). */
  setCount(text: string): void;
  /** Replaces the string of the input field (does not notify an input event). */
  setText(text: string): void;
  readonly text: string;
  /** true: confirmed (RET), false: cancelled (C-g / ESC / cancel). */
  readonly done: Promise<boolean>;
  close(accepted: boolean): void;
}

export interface Minibuffer {
  readonly active: boolean;
  /** If an input is in progress, cancel it (`prompt` ends with null). Used when closing on expiry of an external request. */
  cancel(): void;
  /** The confirmed string. null if cancelled. */
  prompt(
    label: string,
    candidates?: readonly string[],
    options?: PromptOptions,
  ): Promise<string | null>;
  /** Mode that processes on every input (incremental search). */
  live(label: string, handlers: LiveHandlers, initial?: string): LiveSession;
}

/** Puts the candidate string into `parent` with the part matching the query emphasized (textContent, so no HTML injection). */
function appendHighlighted(parent: HTMLElement, text: string, query: string): void {
  let from = 0;
  for (const [start, end] of matchRanges(text, query)) {
    if (start > from) parent.append(document.createTextNode(text.slice(from, start)));
    const mark = document.createElement("b");
    mark.textContent = text.slice(start, end);
    parent.append(mark);
    from = end;
  }
  if (from < text.length) parent.append(document.createTextNode(text.slice(from)));
}

/**
 * RET / ESC for Japanese input (IME) conversion and confirmation. The Enter that confirms arrives with keyCode 229
 * (in WebKit, after the confirmation). Treating it as the minibuffer's RET would confirm and exit at the same time.
 */
function isImeKey(e: KeyboardEvent): boolean {
  return (e.isComposing || e.keyCode === 229) && !e.ctrlKey && !e.metaKey && !e.altKey;
}

export function createMinibuffer(): Minibuffer {
  const mini = byId("minibuffer");
  const input = byId<HTMLInputElement>("prompt-input");
  const list = byId("candidates");
  const labelEl = byId("prompt-label");
  const countEl = byId("prompt-count");
  const histories = new Map<string, string[]>();
  let active = false;
  let cancelCurrent: (() => void) | null = null;

  const open = (label: string, initial = ""): void => {
    active = true;
    labelEl.textContent = label;
    countEl.textContent = "";
    input.value = initial;
    list.replaceChildren();
    mini.hidden = false;
    input.focus();
  };
  // Mac's Option+n (˜), Option+e (´), etc. are dead keys that combine with the next character, and they appear in the input field
  // as conversion text before keydown's preventDefault. Option is used as Meta, so
  // cancel a conversion started by an Option key (restore the input field to its content before the press)
  let optionBase: string | null = null;
  input.addEventListener("keydown", (e) => {
    optionBase = e.altKey && !e.ctrlKey && !e.metaKey ? input.value : null;
  });
  input.addEventListener("compositionstart", () => {
    if (optionBase === null) return;
    const base = optionBase;
    optionBase = null;
    setTimeout(() => {
      input.blur();
      input.value = base;
      input.focus();
      input.dispatchEvent(new Event("input"));
    }, 0);
  });
  const close = (): void => {
    active = false;
    cancelCurrent = null;
    mini.hidden = true;
    input.blur();
  };

  return {
    get active() {
      return active;
    },
    cancel() {
      cancelCurrent?.();
    },
    prompt(label, candidates = [], { allowFree = true, history, initial, source, choose } = {}) {
      return new Promise((resolve) => {
        open(label, initial ?? "");
        let shown: string[] = [];
        let on = 0;
        let current: PromptSource = { items: candidates, prefix: "", fragment: "" };
        let seq = 0;
        let finished = false;
        // History: 0 is the current input. 1 and above are past inputs, newest first.
        const past = history ? (histories.get(history) ?? []) : [];
        let cursor = 0;
        let draft = "";

        const render = (): void => {
          on = Math.min(on, Math.max(0, shown.length - 1));
          countEl.textContent = current.items.length
            ? `${shown.length}/${current.items.length}`
            : "";
          list.replaceChildren(
            ...shown.map((c, i) => {
              const li = document.createElement("li");
              appendHighlighted(li, c, current.fragment);
              li.className = i === on ? "on" : "";
              return li;
            }),
          );
        };
        // When the input changes: derive candidates again (`source` is asynchronous; discard stale results)
        const refresh = async (): Promise<void> => {
          const token = ++seq;
          const next = source
            ? await source(input.value)
            : { items: candidates, prefix: "", fragment: input.value };
          if (token !== seq || finished) return;
          current = next;
          shown = fuzzyFilter(current.items, current.fragment, VISIBLE_CANDIDATES);
          render();
        };
        const done = (value: string | null): void => {
          finished = true;
          close();
          input.removeEventListener("keydown", onKey);
          input.removeEventListener("input", onInput);
          if (history && value) {
            const kept = [value, ...(histories.get(history) ?? []).filter((h) => h !== value)];
            histories.set(history, kept.slice(0, HISTORY_LIMIT));
          }
          resolve(value);
        };
        const onInput = (): void => {
          on = 0;
          cursor = 0;
          void refresh();
        };
        const recall = (step: 1 | -1): void => {
          if (!past.length) return;
          if (cursor === 0) draft = input.value;
          cursor = Math.min(Math.max(cursor + step, 0), past.length);
          input.value = cursor === 0 ? draft : (past[cursor - 1] ?? "");
          on = 0;
          void refresh();
        };
        const accept = (): void => {
          const picked = shown[on] ?? null;
          if (!choose) {
            done(picked ?? (allowFree && input.value ? input.value : null));
            return;
          }
          const choice = choose(picked, input.value, current);
          if (!choice) return;
          if ("text" in choice) {
            input.value = choice.text;
            on = 0;
            void refresh();
          } else done(choice.done);
        };
        const onKey = (e: KeyboardEvent): void => {
          if (isImeKey(e)) return;
          const name = keyName(e);
          if (name === "RET") {
            e.preventDefault();
            accept();
          } else if (name === "C-g" || name === "ESC") {
            e.preventDefault();
            done(null);
          } else if (name === "C-n" || name === "down") {
            e.preventDefault();
            on = Math.min(on + 1, shown.length - 1);
            render();
          } else if (name === "C-p" || name === "up") {
            e.preventDefault();
            on = Math.max(on - 1, 0);
            render();
          } else if (name === "M-p") {
            e.preventDefault();
            recall(1);
          } else if (name === "M-n") {
            e.preventDefault();
            recall(-1);
          } else if (name === "TAB") {
            e.preventDefault();
            const picked = shown[on];
            if (picked) {
              input.value = current.prefix + picked;
              void refresh();
            }
          }
        };
        input.addEventListener("keydown", onKey);
        input.addEventListener("input", onInput);
        cancelCurrent = () => done(null);
        void refresh();
      });
    },
    live(label, handlers, initial = "") {
      open(label, initial);
      let finished = false;
      let finish!: (accepted: boolean) => void;
      const done = new Promise<boolean>((resolve) => {
        finish = resolve;
      });
      const closeSession = (accepted: boolean): void => {
        if (finished) return;
        finished = true;
        close();
        input.removeEventListener("keydown", onKey);
        input.removeEventListener("input", onInput);
        finish(accepted);
      };
      const onInput = (e: Event): void => {
        handlers.onInput(input.value, (e as InputEvent).isComposing === true);
        // Even if focus is lost during processing (by the WebView), keep input possible
        if (document.activeElement !== input) input.focus();
      };
      const onKey = (e: KeyboardEvent): void => {
        if (isImeKey(e)) return;
        const name = keyName(e);
        if (name === "RET") {
          e.preventDefault();
          closeSession(true);
        } else if (name === "C-g" || name === "ESC") {
          e.preventDefault();
          closeSession(false);
        } else if (name && handlers.onKey(name)) {
          e.preventDefault();
        }
      };
      input.addEventListener("keydown", onKey);
      input.addEventListener("input", onInput);
      cancelCurrent = () => closeSession(false);
      return {
        setLabel(text) {
          labelEl.textContent = text;
        },
        setCount(text) {
          countEl.textContent = text;
        },
        setText(text) {
          input.value = text;
        },
        get text() {
          return input.value;
        },
        done,
        close: closeSession,
      };
    },
  };
}
