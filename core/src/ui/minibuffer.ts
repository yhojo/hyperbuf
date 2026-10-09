// ミニバッファ。検索・候補選択・確認は、ダイアログではなく、画面下部のここで行う。
// 入力欄にフォーカスがあるあいだは、C-f/C-b/C-a/C-e などは WebView 既定の文字移動に任せる
// (確定・取消・候補選択のキーだけを扱う。Emacs のミニバッファと同じ振る舞い)。
//
// 2 つの使い方:
//  - prompt: 候補つきの入力(あいまい絞り込み)。M-p / M-n で、同じ種類の入力の履歴をたどる
//  - live:   入力のたびに処理する(インクリメンタル検索)。特別なキー(C-s、C-r など)は、呼び出し側が扱う

import { fuzzyFilter, matchRanges } from "../fuzzy.ts";
import { keyName } from "../keys.ts";
import { byId } from "./dom.ts";

/** 候補を表示する件数。 */
export const VISIBLE_CANDIDATES = 10;
/** 入力の履歴を、種類ごとに保つ件数。 */
const HISTORY_LIMIT = 50;

export interface PromptOptions {
  /** 候補にない自由な入力を受け付けるか。既定は true。 */
  allowFree?: boolean;
  /** 入力の履歴の種類(M-p / M-n でたどる)。省略すると、履歴は使わない。 */
  history?: string;
}

export interface LiveHandlers {
  /** 入力が変わった。 */
  onInput(text: string): void;
  /**
   * 特別なキー。RET(確定)と C-g / ESC(取消)以外で、呼び出し側が扱うもの(C-s、C-r など)。
   * 扱ったら true(既定の動作を止める)。
   */
  onKey(name: string): boolean;
}

export interface LiveSession {
  /** 入力欄の左の見出し(状態の表示)を変える。 */
  setLabel(text: string): void;
  /** 入力欄の右の表示(一致の番号・件数など)を変える。 */
  setCount(text: string): void;
  /** 入力欄の文字列を置き換える(入力の通知は、しない)。 */
  setText(text: string): void;
  readonly text: string;
  /** true: 確定(RET)、false: 取消(C-g / ESC / cancel)。 */
  readonly done: Promise<boolean>;
  close(accepted: boolean): void;
}

export interface Minibuffer {
  readonly active: boolean;
  /** 入力中なら、取り消す(`prompt` は null で終わる)。外部の要求の期限切れで閉じるときに使う。 */
  cancel(): void;
  /** 確定した文字列。取り消したら null。 */
  prompt(
    label: string,
    candidates?: readonly string[],
    options?: PromptOptions,
  ): Promise<string | null>;
  /** 入力のたびに処理するモード(インクリメンタル検索)。 */
  live(label: string, handlers: LiveHandlers, initial?: string): LiveSession;
}

/** 候補の文字列を、検索語に一致した部分を強調して、`parent` に入れる(textContent なので、HTML の注入はない)。 */
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
    prompt(label, candidates = [], { allowFree = true, history } = {}) {
      return new Promise((resolve) => {
        open(label);
        let shown: string[] = [];
        let on = 0;
        // 履歴: 0 が、現在の入力。1 以上は、新しいものから順に、過去の入力。
        const past = history ? (histories.get(history) ?? []) : [];
        let cursor = 0;
        let draft = "";

        const update = (): void => {
          shown = fuzzyFilter(candidates, input.value, VISIBLE_CANDIDATES);
          on = Math.min(on, Math.max(0, shown.length - 1));
          countEl.textContent = candidates.length ? `${shown.length}/${candidates.length}` : "";
          list.replaceChildren(
            ...shown.map((c, i) => {
              const li = document.createElement("li");
              appendHighlighted(li, c, input.value);
              li.className = i === on ? "on" : "";
              return li;
            }),
          );
        };
        const done = (value: string | null): void => {
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
          update();
        };
        const recall = (step: 1 | -1): void => {
          if (!past.length) return;
          if (cursor === 0) draft = input.value;
          cursor = Math.min(Math.max(cursor + step, 0), past.length);
          input.value = cursor === 0 ? draft : (past[cursor - 1] ?? "");
          on = 0;
          update();
        };
        const onKey = (e: KeyboardEvent): void => {
          const name = keyName(e);
          if (name === "RET") {
            e.preventDefault();
            done(shown[on] ?? (allowFree && input.value ? input.value : null));
          } else if (name === "C-g" || name === "ESC") {
            e.preventDefault();
            done(null);
          } else if (name === "C-n" || name === "down") {
            e.preventDefault();
            on = Math.min(on + 1, shown.length - 1);
            update();
          } else if (name === "C-p" || name === "up") {
            e.preventDefault();
            on = Math.max(on - 1, 0);
            update();
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
              input.value = picked;
              update();
            }
          }
        };
        input.addEventListener("keydown", onKey);
        input.addEventListener("input", onInput);
        cancelCurrent = () => done(null);
        update();
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
      const onInput = (): void => {
        handlers.onInput(input.value);
        // 処理の中でフォーカスが外れても(WebView による)、続けて入力できるようにする
        if (document.activeElement !== input) input.focus();
      };
      const onKey = (e: KeyboardEvent): void => {
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
