// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Assembles the app. Ties together state (model), components (echo area, minibuffer, rendering), commands, key input,
// and events from the host.

import type { HostConfig, HyperbufHost } from "../host.ts";
import { createModel, currentEntry, isVirtualPath, openBuffer, windows } from "../model.ts";
import type { Model } from "../model.ts";
import type { Renderer } from "../pipeline.ts";
import { createCommands } from "./commands.ts";
import type { Commands } from "./commands.ts";
import type { AppContext } from "./context.ts";
import { byId } from "./dom.ts";
import { createEcho } from "./echo.ts";
import { wireHostEvents } from "./host-events.ts";
import { installKeyboard } from "./keyboard.ts";
import type { KeyboardHandle } from "./keyboard.ts";
import { createKeymap } from "../keys.ts";
import { resolveBindings } from "./keymap.ts";
import { createMinibuffer } from "./minibuffer.ts";
import { follow, openAt } from "./navigation.ts";
import { searchProject } from "./search.ts";
import { applySelection } from "./selection-state.ts";
import { createSessionSaver, restoreSession } from "./session.ts";
import type { SessionSaver } from "./session.ts";
import { refreshMermaidTheme } from "./diagrams.ts";
import { Views } from "./windows.ts";

export interface AppHandle {
  ctx: AppContext;
  commands: Commands;
  keyboard: KeyboardHandle;
  /** Opens a document in the selected window and renders it (for external integration and tests). */
  open(path: string, anchor?: string | null): Promise<void>;
  search(query: string): Promise<void>;
  /** Saves the session right now (the shell calls this just before the app quits). */
  flushSession(): Promise<void>;
}

export async function startApp(options: {
  host: HyperbufHost;
  renderer: Renderer;
}): Promise<AppHandle> {
  const { host, renderer } = options;
  const model = createModel();
  const echo = createEcho(byId("echo"), byId("status"));
  const minibuffer = createMinibuffer();

  const views: Views = new Views({
    frame: byId("frame"),
    model,
    renderer,
    resolveResource: host.resolveResource?.bind(host) ?? ((path) => path),
    home: host.home,
    vcsBranch: host.vcsBranch?.bind(host),
    onSelect: (win) => {
      model.selected = win.id;
      views.refresh();
    },
    onFollow: (win, href) => {
      void follow(ctx, win, href).then(() => views.refresh());
    },
    onChange: () => {
      saver?.schedule();
      syncWatch();
    },
  });
  let saver: SessionSaver | undefined;
  let watched = new Set<string>();
  /** Tells the host which files are displayed. Newly displayed ones are re-read and updated if stale. */
  const syncWatch = (): void => {
    const now = new Set(displayedPaths(model));
    host.watch?.([...now]);
    const added = [...now].filter((p) => !watched.has(p));
    watched = now;
    for (const path of added) void revalidate(path);
  };
  /** Checks buffer contents against files (picks up changes and deletions made while not watching). */
  const revalidate = async (path: string): Promise<void> => {
    const buf = model.buffers.get(path);
    if (!buf) return;
    try {
      const text = await host.readFile(path);
      if (text !== buf.text || buf.missing) {
        openBuffer(model, path, text);
        buf.missing = false;
        views.refresh();
      }
    } catch {
      if (!buf.missing) {
        buf.missing = true;
        views.refresh();
      }
    }
  };
  // Layers the user's key bindings (`keybindings` in config.json) over the defaults. Problematic settings are ignored and reported
  const config: HostConfig | undefined = await host.getConfig?.().catch(() => undefined);
  renderer.configure({ mathUnescapeUnderscore: config?.mathUnescapeUnderscore !== false });
  views.followUpdates = config?.followUpdates === true;
  views.showVcsBranch = config?.modeLineVcsBranch !== false;
  const bindings = resolveBindings(config?.keybindings);
  const ctx: AppContext = {
    host,
    model,
    views,
    echo,
    minibuffer,
    bindings,
    problems: config?.problems ?? [],
  };

  const commands = createCommands(ctx);
  const keyboard = installKeyboard(ctx, commands, createKeymap(bindings.bindings));

  const useSession = config?.restoreSession !== false && !!host.saveSession;
  const restored = useSession ? await restoreSession(ctx) : null;
  views.refresh();
  if (restored) {
    if (restored.selection) applySelection(ctx, restored.selection);
    echo.message("Previous session restored");
  } else {
    echo.message("Type C-x C-f to open a file");
  }
  // When the OS appearance (light / dark) changes while the app is running, re-render diagrams (Mermaid) whose colors are fixed at render time.
  // Documents, code, math and the UI follow automatically via CSS (`prefers-color-scheme`)
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    void refreshMermaidTheme().then(() => views.redrawDiagrams());
  });
  // When the app becomes active, check the displayed files (a safety net for cases the watcher misses)
  window.addEventListener("focus", () => {
    for (const path of watched) void revalidate(path);
    views.refreshBranches();
  });
  // Saving before restoring would erase the previous state. Start after the restore (or the initial display)
  if (useSession) {
    saver = createSessionSaver(ctx);
    const flushNow = (): void => void saver?.flush();
    window.addEventListener("pagehide", flushNow);
    document.addEventListener("selectionchange", () => saver?.schedule());
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") flushNow();
    });
  }
  wireHostEvents(ctx, commands);
  const problemCount = bindings.problems.length + ctx.problems.length;
  if (problemCount) {
    echo.message(`Configuration: ${problemCount} problem(s) (see C-h b)`);
  }

  return {
    ctx,
    commands,
    keyboard,
    async open(path, anchor = null) {
      await openAt(ctx, path, anchor);
      views.refresh();
    },
    async search(query) {
      await searchProject(ctx, query);
      views.refresh();
    },
    async flushSession() {
      await saver?.flush();
    },
  };
}

/** Paths of the files shown by all windows (no duplicates). */
function displayedPaths(model: Model): string[] {
  const out = new Set<string>();
  for (const win of windows(model)) {
    const entry = currentEntry(win);
    if (entry && !isVirtualPath(entry.path)) out.add(entry.path);
  }
  return [...out];
}
