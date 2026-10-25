// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Trackpad / mouse gestures for moving in the reference history (setting `gestureNavigation`).
//
// - Swipe between pages (trackpad, Magic Mouse): the shell enables WebKit's own back / forward gesture
//   (`allowsBackForwardNavigationGestures`), so the direction, the animation and the macOS "Swipe between pages" setting are
//   handled by the system. WebKit's history is only a *carrier* for the gesture: it always holds three entries
//   `[back, here, forward]` (all the same document, made with `pushState`) and we stay on the middle one. When a swipe lands on
//   `back` / `forward`, the real reference history moves (the Web core's `back` / `forward`) and we step back to the middle entry.
// - Mouse back / forward buttons (button 3 / 4).

import type { Win } from "../model.ts";

export type HistoryDirection = "back" | "forward";

type Marker = "back" | "here" | "forward";

/** `history.state` of the three carrier entries. */
export function markerOf(state: unknown): Marker | null {
  const mark = (state as { hyperbufHistory?: unknown } | null)?.hyperbufHistory;
  return mark === "back" || mark === "here" || mark === "forward" ? mark : null;
}

/** Which reference-history move a `popstate` state asks for (null: the middle entry or a foreign state). */
export function swipeDirection(state: unknown): HistoryDirection | null {
  const marker = markerOf(state);
  return marker === "back" || marker === "forward" ? marker : null;
}

/** Maps a MouseEvent button to a direction (3: the mouse's back button, 4: forward). */
export function buttonDirection(button: number): HistoryDirection | null {
  return button === 3 ? "back" : button === 4 ? "forward" : null;
}

export interface GestureOptions {
  /** Window whose content contains the element (null: not inside a window). */
  windowOf(target: Element): Win | null;
  /** The selected window (the target of a swipe, which has no pointer position). */
  selected(): Win;
  /** Select the window and move in its history. */
  navigate(win: Win, direction: HistoryDirection): void;
  /** Gestures are ignored while this returns false (minibuffer input). */
  enabled(): boolean;
}

/** Sets up the three carrier entries and listens for swipes and mouse buttons. */
export function installGestures(options: GestureOptions): void {
  let recentering = true; // until the first step back to the middle entry has happened
  // [back, here, forward] with the current position on `here`
  history.replaceState({ hyperbufHistory: "back" }, "");
  history.pushState({ hyperbufHistory: "here" }, "");
  history.pushState({ hyperbufHistory: "forward" }, "");
  history.go(-1);

  window.addEventListener("popstate", (e) => {
    const marker = markerOf(e.state);
    if (marker === "here") {
      recentering = false;
      return;
    }
    if (recentering || !marker) return;
    recentering = true;
    // Back to the middle entry before moving in the real history, so the next swipe has both neighbours again
    history.go(marker === "back" ? 1 : -1);
    const direction = swipeDirection(e.state);
    if (direction && options.enabled()) options.navigate(options.selected(), direction);
  });

  const onMouseUp = (e: MouseEvent): void => {
    const direction = buttonDirection(e.button);
    if (!direction || !options.enabled()) return;
    if (!(e.target instanceof Element)) return;
    const win = options.windowOf(e.target);
    if (!win) return;
    e.preventDefault();
    options.navigate(win, direction);
  };
  // Some WebKit versions also navigate on these buttons by default; the mousedown guard keeps the page from reacting
  const onMouseDown = (e: MouseEvent): void => {
    if (buttonDirection(e.button) && options.enabled()) e.preventDefault();
  };
  window.addEventListener("mouseup", onMouseUp);
  window.addEventListener("mousedown", onMouseDown);
}
