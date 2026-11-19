// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Minibuffer. Search, candidate selection and confirmation happen here at the bottom of the screen, not in dialogs.
// While the input field has focus, C-f/C-b/C-a/C-e etc. edit the input line instead of running commands
// (same behavior as the Emacs minibuffer). The line-editing keys are a fixed keymap (`../lineedit.ts`,
// docs/dev/interaction-model.md §6.3), handled in `prompt`; `live` (incremental search) still leaves them to the WebView.
//
// Two modes of use:
//  - prompt: input with candidates (fuzzy narrowing). M-p / M-n walk the history of inputs of the same kind
//  - live:   process on every input (incremental search). Special keys (C-s, C-r, etc.) are handled by the caller

import { fuzzyFilter, matchRanges } from "../fuzzy.ts";
import { keyName } from "../keys.ts";
import { createLineEditor, isLineEditKey, YANK_KEY } from "../lineedit.ts";
import type { Line } from "../lineedit.ts";
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

/** The system clipboard, reached through the host contract. Without it the kill ring works on its own. */
export interface Clipboard {
  read(): Promise<string | null>;
  write(text: string): void;
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

export function createMinibuffer(clipboard?: Clipboard): Minibuffer {
  const mini = byId("minibuffer");
  const input = byId<HTMLInputElement>("prompt-input");
  const list = byId("candidates");
  const labelEl = byId("prompt-label");
  const countEl = byId("prompt-count");
  const histories = new Map<string, string[]>();
  let active = false;
  let cancelCurrent: (() => void) | null = null;
  // One kill ring for every prompt of this frame (in memory only)
  const editor = createLineEditor();
  /** Counts prompts, so that a clipboard read that returns late does not edit the next prompt. */
  let generation = 0;
  /** Line edits waiting for the clipboard. While there are any, later edits wait behind them to keep the key order. */
  let waiting = 0;
  let edits: Promise<void> = Promise.resolve();
  /** The `input` event comes from a line edit, not from typing. */
  let applying = false;

  // WebKit does not scroll a text field to a cursor moved by script (C-a on a long path would leave the cursor out of
  // sight), so measure where the cursor is and scroll the field to it
  let measure: CanvasRenderingContext2D | null = null;
  const revealCursor = (point: number): void => {
    measure ??= document.createElement("canvas").getContext("2d");
    if (!measure) return;
    const style = getComputedStyle(input);
    measure.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const x = measure.measureText(input.value.slice(0, point)).width;
    const width =
      input.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    const margin = Math.min(parseFloat(style.fontSize), width / 4);
    if (x - margin < input.scrollLeft) input.scrollLeft = Math.max(0, x - margin);
    else if (x + margin > input.scrollLeft + width) input.scrollLeft = x + margin - width;
  };

  const applyEdit = (name: string, clipboardText: string | null): void => {
    const before = input.value;
    const end = input.selectionEnd ?? before.length;
    const line: Line = {
      text: before,
      start: input.selectionStart ?? end,
      end,
      backward: input.selectionDirection === "backward",
    };
    const edit = editor.key(name, line, clipboardText);
    if (!edit) return;
    if (edit.copy !== undefined) clipboard?.write(edit.copy);
    if (edit.line.text !== before) input.value = edit.line.text;
    input.setSelectionRange(edit.line.start, edit.line.end);
    revealCursor(edit.line.end);
    if (edit.line.text === before) return;
    applying = true;
    input.dispatchEvent(new Event("input"));
    applying = false;
  };
  /** Handles a line-editing key. false if `name` is not one, or a conversion (IME) is in progress. */
  const editKey = (e: KeyboardEvent, name: string): boolean => {
    if (!isLineEditKey(name) || e.isComposing) return false;
    e.preventDefault();
    const needsClipboard = name === YANK_KEY && clipboard !== undefined;
    if (!needsClipboard && waiting === 0) {
      applyEdit(name, null);
      return true;
    }
    const opened = generation;
    waiting++;
    edits = edits.then(async () => {
      const text = needsClipboard ? await clipboard.read().catch(() => null) : null;
      waiting--;
      if (active && opened === generation) applyEdit(name, text);
    });
    return true;
  };
  // Mac's Option is used as Meta, but Option+key also types: Option+n (˜), Option+e (´) etc. are dead keys, and with
  // a Japanese input source every Option+letter starts a conversion holding a symbol (`∫` for M-b). Either way a
  // conversion starts that keydown's preventDefault cannot stop, so cancel it: put the line back as it was.
  // The two events come in either order:
  //  - keydown, then compositionstart: the key has been handled already; only undo the conversion
  //  - compositionstart, then a keydown marked as part of the conversion: undo it and deliver the key again as a plain one
  interface LineState {
    value: string;
    start: number;
    end: number;
  }
  /** The line when a conversion started, until the next keydown. */
  let composition: LineState | null = null;
  /** The last keydown was Option+key, and its key is still down (a conversion starting now comes from it). */
  let optionKey = false;
  let optionTimer: ReturnType<typeof setTimeout> | undefined;
  /** A key is being delivered again after its conversion was cancelled. */
  let redelivering = false;
  /** Typing in a conversion that has not been committed yet. */
  let uncommitted = false;
  /** Undoing a conversion started by an Option key: what it does to the line is not typing. */
  let cancelling = false;
  const cancelComposition = (line: LineState, again: KeyboardEventInit | null): void => {
    cancelling = true;
    setTimeout(() => {
      input.blur();
      input.value = line.value;
      input.focus();
      input.setSelectionRange(line.start, line.end);
      uncommitted = false;
      cancelling = false;
      // The conversion text went through the `input` handlers: let them see the line as it is again
      applying = true;
      input.dispatchEvent(new Event("input"));
      applying = false;
      if (!again) return;
      redelivering = true;
      input.dispatchEvent(new KeyboardEvent("keydown", again));
      redelivering = false;
    }, 0);
  };
  input.addEventListener("compositionstart", () => {
    const end = input.selectionEnd ?? input.value.length;
    const line = { value: input.value, start: input.selectionStart ?? end, end };
    if (optionKey) {
      optionKey = false;
      cancelComposition(line, null);
    } else composition = line;
  });
  input.addEventListener(
    "keydown",
    (e) => {
      const started = composition;
      composition = null;
      const option = e.altKey && !e.ctrlKey && !e.metaKey;
      clearTimeout(optionTimer);
      optionKey = option && !redelivering;
      // Do not take a later conversion (typing kana) for this key's
      if (optionKey) optionTimer = setTimeout(() => (optionKey = false), 200);
      if (!started || !e.isComposing || !option) return;
      optionKey = false;
      e.preventDefault();
      e.stopImmediatePropagation();
      const { key, code, shiftKey } = e;
      cancelComposition(started, {
        key,
        code,
        shiftKey,
        altKey: true,
        bubbles: true,
        cancelable: true,
      });
    },
    true,
  );
  input.addEventListener("keyup", () => {
    optionKey = false;
  });
  // Typing, moving the cursor with other keys or the mouse: the next kill starts a new entry, and M-y no longer applies.
  // Text in a conversion counts once it is committed (a conversion cancelled above never is)
  input.addEventListener("input", (e) => {
    if (applying || cancelling) return;
    if ((e as InputEvent).isComposing) uncommitted = true;
    else editor.reset();
  });
  input.addEventListener("compositionend", () => {
    if (uncommitted && !cancelling) editor.reset();
    uncommitted = false;
  });
  input.addEventListener("mousedown", () => editor.reset());
  input.addEventListener("keydown", (e) => {
    const name = keyName(e);
    if (name && !isLineEditKey(name)) editor.reset();
  });

  const open = (label: string, initial = ""): void => {
    active = true;
    generation++;
    editor.reset();
    labelEl.textContent = label;
    countEl.textContent = "";
    input.value = initial;
    list.replaceChildren();
    mini.hidden = false;
    input.focus();
  };
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
          } else if (name) editKey(e, name);
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
