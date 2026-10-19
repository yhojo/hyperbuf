// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Global key input. Key sequence -> command mapping, and serial execution of commands.

import { createDispatcher, keyName } from "../keys.ts";
import type { Keymap } from "../keys.ts";
import type { Commands } from "./commands.ts";
import type { AppContext } from "./context.ts";
import { errorMessage } from "./navigation.ts";
import { LatencyRecorder } from "./latency.ts";

export interface KeyboardHandle {
  readonly latency: LatencyRecorder;
  /** Waits until all commands accepted so far have finished (for tests). */
  idle(): Promise<void>;
}

export function installKeyboard(
  ctx: AppContext,
  commands: Commands,
  keymap: Keymap,
): KeyboardHandle {
  const dispatcher = createDispatcher(keymap);
  const latency = new LatencyRecorder();
  // Run serially so that the next key is not processed before an asynchronous command (file loading etc.) completes
  let queue: Promise<void> = Promise.resolve();

  window.addEventListener("keydown", (e) => {
    if (ctx.minibuffer.active) return; // the input field has its own key handling
    const name = keyName(e);
    if (!name) return;
    const t0 = e.timeStamp;
    if (name === "C-g") {
      dispatcher.reset();
      e.preventDefault();
      ctx.echo.message("Quit");
      return;
    }
    const r = dispatcher.feed(name);
    if (r.type === "unbound") {
      if (r.keys.length > 1) {
        e.preventDefault();
        ctx.echo.message(`${r.keys.join(" ")} is undefined`);
      }
      return; // leave a lone unassigned key to the WebView default (Cmd+C etc.)
    }
    e.preventDefault();
    if (r.type === "prefix") {
      ctx.echo.message(`${r.pending.join(" ")} -`);
      return;
    }
    ctx.echo.message("");
    const command = commands[r.command as keyof Commands];
    queue = queue.then(async () => {
      try {
        await command();
      } catch (err) {
        ctx.echo.message(`${r.command}: ${errorMessage(err)}`);
      }
      ctx.views.refresh();
      latency.record(t0, (ms, s) => {
        ctx.echo.status(
          `${ctx.host.name} | ${name} → ${r.command}: ${ms.toFixed(1)}ms (render ${ctx.views.stats.ms.toFixed(1)}ms ${ctx.views.stats.diagrams}) | median ${s.median.toFixed(1)} / p95 ${s.p95.toFixed(1)} / max ${s.max.toFixed(1)} (n=${s.n})`,
        );
      });
    });
  });

  return { latency, idle: () => queue };
}
