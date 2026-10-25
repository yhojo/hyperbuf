// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Trackpad / mouse gestures for moving in the reference history (setting `gestureNavigation`).
//
// - Two-finger horizontal swipe: right = back, left = forward (the default macOS direction, "natural scrolling" on).
// - Mouse back / forward buttons (button 3 / 4).
//
// WebKit's own history gestures are not used: the reference history is the Web core's, not WebKit's.
// The decision logic here is pure so it can be tested without a DOM; `installGestures` does the wiring.

import type { Win } from "../model.ts";

export type HistoryDirection = "back" | "forward";

/** Accumulated horizontal distance (px) that counts as a swipe. */
export const SWIPE_THRESHOLD_PX = 120;
/** The horizontal distance must exceed this multiple of the vertical one (ignores diagonal / vertical scrolling). */
export const SWIPE_DOMINANCE = 2;
/** Wheel events further apart than this (ms) belong to different gestures. Inertia events keep the previous gesture locked. */
export const GESTURE_IDLE_MS = 200;

/** The scroll-related state of one element on the path from the event target up to the window content. */
export interface ScrollAxisInfo {
  overflowX: string;
  scrollLeft: number;
  scrollWidth: number;
  clientWidth: number;
}

/** Whether something under the pointer can still scroll horizontally in the direction of `dx` (then the swipe is a scroll, not navigation). */
export function canScrollHorizontally(path: readonly ScrollAxisInfo[], dx: number): boolean {
  return path.some((el) => {
    if (el.overflowX !== "auto" && el.overflowX !== "scroll") return false;
    const max = el.scrollWidth - el.clientWidth;
    if (max <= 1) return false;
    return dx < 0 ? el.scrollLeft > 0 : el.scrollLeft < max - 1;
  });
}

/**
 * Turns a stream of wheel events into at most one navigation per gesture.
 * Once a gesture fires (or starts on something that scrolls horizontally) it stays locked until the events stop for `GESTURE_IDLE_MS`,
 * so the inertia tail of a swipe does not navigate twice.
 */
export class SwipeTracker {
  private lastTime = Number.NEGATIVE_INFINITY;
  private accX = 0;
  private accY = 0;
  private locked = false;

  /**
   * Feeds one wheel event. `blocked(dx)` is asked only at the start of a gesture
   * (true: the pointer is over horizontally scrollable content, so the whole gesture is left alone).
   */
  feed(
    dx: number,
    dy: number,
    time: number,
    blocked: (dx: number) => boolean,
  ): HistoryDirection | null {
    if (time - this.lastTime > GESTURE_IDLE_MS) {
      this.accX = 0;
      this.accY = 0;
      this.locked = dx !== 0 && blocked(dx);
    }
    this.lastTime = time;
    if (this.locked) return null;
    this.accX += dx;
    this.accY += dy;
    if (Math.abs(this.accX) < SWIPE_THRESHOLD_PX) return null;
    if (Math.abs(this.accX) < SWIPE_DOMINANCE * Math.abs(this.accY)) return null;
    this.locked = true;
    // Fingers moving right scroll the content left (negative deltaX): that is "back", as in Safari
    return this.accX < 0 ? "back" : "forward";
  }
}

/** Maps a MouseEvent button to a direction (3: the mouse's back button, 4: forward). */
export function buttonDirection(button: number): HistoryDirection | null {
  return button === 3 ? "back" : button === 4 ? "forward" : null;
}

export interface GestureOptions {
  /** Window whose content contains the element (null: not inside a window). */
  windowOf(target: Element): Win | null;
  /** Select the window and move in its history. */
  navigate(win: Win, direction: HistoryDirection): void;
  /** Gestures are ignored while this returns false (minibuffer input, setting off). */
  enabled(): boolean;
  /** The element that scrolls the window (the path from the target stops here). */
  contentOf(win: Win): HTMLElement | undefined;
}

/** Listens for swipes and mouse buttons. Returns a function that removes the listeners. */
export function installGestures(options: GestureOptions): () => void {
  const tracker = new SwipeTracker();
  const pathOf = (target: Element, content: HTMLElement): ScrollAxisInfo[] => {
    const path: ScrollAxisInfo[] = [];
    for (let el: Element | null = target; el; el = el.parentElement) {
      path.push({
        overflowX: getComputedStyle(el).overflowX,
        scrollLeft: el.scrollLeft,
        scrollWidth: el.scrollWidth,
        clientWidth: el.clientWidth,
      });
      if (el === content) break;
    }
    return path;
  };
  const onWheel = (e: WheelEvent): void => {
    // ctrl + wheel is pinch zoom; vertical-only events can never navigate
    if (e.ctrlKey || e.deltaX === 0 || !options.enabled()) return;
    if (!(e.target instanceof Element)) return;
    const win = options.windowOf(e.target);
    const content = win && options.contentOf(win);
    if (!win || !content) return;
    const target = e.target;
    const direction = tracker.feed(e.deltaX, e.deltaY, e.timeStamp, (dx) =>
      canScrollHorizontally(pathOf(target, content), dx),
    );
    if (direction) options.navigate(win, direction);
  };
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
  window.addEventListener("wheel", onWheel, { passive: true });
  window.addEventListener("mouseup", onMouseUp);
  window.addEventListener("mousedown", onMouseDown);
  return () => {
    window.removeEventListener("wheel", onWheel);
    window.removeEventListener("mouseup", onMouseUp);
    window.removeEventListener("mousedown", onMouseDown);
  };
}
