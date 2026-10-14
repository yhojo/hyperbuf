// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// アプリの組み立て。状態(model)、部品(エコー・ミニバッファ・描画)、コマンド、キー入力、
// ホストからのイベントを結びつける。

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
  /** 選択中の window で文書を開き、描画する(外部連携・テスト用)。 */
  open(path: string, anchor?: string | null): Promise<void>;
  search(query: string): Promise<void>;
  /** セッションを、いますぐ保存する(アプリの終了の直前に、シェルが呼ぶ)。 */
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
  /** 表示中のファイルを、ホストに伝える。新しく表示されたものは、読み直して、古ければ更新する。 */
  const syncWatch = (): void => {
    const now = new Set(displayedPaths(model));
    host.watch?.([...now]);
    const added = [...now].filter((p) => !watched.has(p));
    watched = now;
    for (const path of added) void revalidate(path);
  };
  /** バッファの内容を、ファイルと照らし合わせる(監視していない間の変更・削除を拾う)。 */
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
  // 利用者のキー割り当て(config.json の keybindings)を、標準に重ねる。問題のある設定は、無視して、知らせる
  const config: HostConfig | undefined = await host.getConfig?.().catch(() => undefined);
  renderer.configure({ mathUnescapeUnderscore: config?.mathUnescapeUnderscore !== false });
  views.followUpdates = config?.followUpdates === true;
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
  // アプリの動作中に OS の外観(ライト / ダーク)が切り替わったら、描画時に色が決まる図(Mermaid)を、描き直す。
  // 文書・コード・数式・UI は、CSS(`prefers-color-scheme`)が、そのまま追従する
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    void refreshMermaidTheme().then(() => views.redrawDiagrams());
  });
  // アプリがアクティブになったときに、表示中のファイルを照合する(監視で拾えない場合の保険)
  window.addEventListener("focus", () => {
    for (const path of watched) void revalidate(path);
  });
  // 復元の前に保存すると、前回の状態を消してしまう。復元(または、初期表示)のあとに始める
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

/** 全 window が表示している、ファイルの文書のパス(重複なし)。 */
function displayedPaths(model: Model): string[] {
  const out = new Set<string>();
  for (const win of windows(model)) {
    const entry = currentEntry(win);
    if (entry && !isVirtualPath(entry.path)) out.add(entry.path);
  }
  return [...out];
}
