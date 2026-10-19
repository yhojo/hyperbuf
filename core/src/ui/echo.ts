// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Echo area (messages) and status line at the bottom of the screen. No dialogs are used.

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
