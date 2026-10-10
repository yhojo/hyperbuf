// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

export function byId<T extends HTMLElement = HTMLElement>(id: string): T {
  const el = document.getElementById(id);
  if (!el) throw new Error(`#${id} がありません`);
  return el as T;
}
