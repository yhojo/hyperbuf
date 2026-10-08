// ミニバッファ。検索・候補選択・確認は、ダイアログではなく、画面下部のここで行う。
// 入力欄にフォーカスがあるあいだは、C-f/C-b/C-a/C-e などは WebView 既定の文字移動に任せる
// (確定・取消・候補選択のキーだけを扱う。Emacs のミニバッファと同じ振る舞い)。

import { fuzzyFilter } from "../fuzzy.ts";
import { keyName } from "../keys.ts";
import { byId } from "./dom.ts";

export interface PromptOptions {
  /** 候補にない自由な入力を受け付けるか。既定は true。 */
  allowFree?: boolean;
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
}

export function createMinibuffer(): Minibuffer {
  const mini = byId("minibuffer");
  const input = byId<HTMLInputElement>("prompt-input");
  const list = byId("candidates");
  const labelEl = byId("prompt-label");
  let active = false;
  let cancelCurrent: (() => void) | null = null;

  return {
    get active() {
      return active;
    },
    cancel() {
      cancelCurrent?.();
    },
    prompt(label, candidates = [], { allowFree = true } = {}) {
      return new Promise((resolve) => {
        active = true;
        labelEl.textContent = label;
        input.value = "";
        mini.hidden = false;
        input.focus();
        let shown: string[] = [];
        let on = 0;

        const update = (): void => {
          shown = fuzzyFilter(candidates, input.value, 8);
          on = Math.min(on, Math.max(0, shown.length - 1));
          list.replaceChildren(
            ...shown.map((c, i) => {
              const li = document.createElement("li");
              li.textContent = c;
              li.className = i === on ? "on" : "";
              return li;
            }),
          );
        };
        const done = (value: string | null): void => {
          active = false;
          cancelCurrent = null;
          mini.hidden = true;
          input.removeEventListener("keydown", onKey);
          input.removeEventListener("input", onInput);
          input.blur();
          resolve(value);
        };
        const onInput = (): void => {
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
  };
}
