// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 画面下部のエコー領域(メッセージ)とステータス行。ダイアログは使わない。

export interface Echo {
  message(text: string): void;
  status(text: string): void;
}

export function createEcho(messageEl: HTMLElement, statusEl: HTMLElement): Echo {
  return {
    message: (text) => {
      messageEl.textContent = text;
    },
    status: (text) => {
      statusEl.textContent = text;
    },
  };
}
