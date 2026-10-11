// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// 画面の選択・クリックから、指したブロックと選択を求める(DOM の部分)。
// 元の位置への対応づけ(純粋な部分)は、../locate.ts。

import { locateInSource } from "../locate.ts";
import type { SourceLocation } from "../locate.ts";

/** 元の位置を持つ、最も内側のブロック。 */
function blockOf(node: Node | null): HTMLElement | null {
  const element = node instanceof HTMLElement ? node : (node?.parentElement ?? null);
  return element?.closest<HTMLElement>("[data-source-start]") ?? null;
}

function range(el: HTMLElement): { start: number; end: number } | null {
  const start = Number(el.dataset["sourceStart"]);
  const end = Number(el.dataset["sourceEnd"]);
  return Number.isFinite(start) && Number.isFinite(end) ? { start, end } : null;
}

/** 画面の上端にあるブロック(選択もクリックもないときの、「いま読んでいる場所」)。 */
function topBlock(content: HTMLElement): HTMLElement | null {
  let best: HTMLElement | null = null;
  for (const el of content.querySelectorAll<HTMLElement>("[data-source-start]")) {
    if (el.offsetTop <= content.scrollTop + 1) best = el;
    else break;
  }
  return best ?? content.querySelector<HTMLElement>("[data-source-start]");
}

export interface LocateRequest {
  content: HTMLElement;
  path: string;
  text: string;
  version: number;
  /** 右クリックした要素(選択がないとき、これが指した場所になる)。 */
  contextTarget: Element | null;
}

/**
 * ビューアで指した場所を、元の Markdown の位置にする。
 * 優先順: (1) 文書内の、空でない選択 (2) 右クリックした要素 (3) 画面の上端のブロック。
 */
export function locateFromDom(request: LocateRequest): SourceLocation | null {
  const { content } = request;
  const selection = window.getSelection();
  let startBlock: HTMLElement | null = null;
  let endBlock: HTMLElement | null = null;
  let selected = "";

  if (selection && !selection.isCollapsed && selection.rangeCount > 0) {
    const r = selection.getRangeAt(0);
    if (content.contains(r.startContainer) && content.contains(r.endContainer)) {
      startBlock = blockOf(r.startContainer);
      endBlock = blockOf(r.endContainer);
      selected = selection.toString();
    }
  }
  if (!startBlock && request.contextTarget && content.contains(request.contextTarget)) {
    startBlock = endBlock = blockOf(request.contextTarget);
  }
  if (!startBlock) startBlock = endBlock = topBlock(content);
  if (!startBlock || !endBlock) return null;

  const a = range(startBlock);
  const b = range(endBlock);
  if (!a || !b) return null;
  return locateInSource({
    path: request.path,
    text: request.text,
    version: request.version,
    // 複数のブロックにまたがる選択は、その全体(曖昧なので、block になる)
    blockStart: Math.min(a.start, b.start),
    blockEnd: Math.max(a.end, b.end),
    selection: startBlock === endBlock ? selected : "",
  });
}
