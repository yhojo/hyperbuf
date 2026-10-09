// アプリの組み立て。状態(model)、部品(エコー・ミニバッファ・描画)、コマンド、キー入力、
// ホストからのイベントを結びつける。

import type { HostConfig, HyperbufHost } from "../host.ts";
import { createModel } from "../model.ts";
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
import { createSessionSaver, restoreSession } from "./session.ts";
import type { SessionSaver } from "./session.ts";
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
    onSelect: (win) => {
      model.selected = win.id;
      views.refresh();
    },
    onFollow: (win, href) => {
      void follow(ctx, win, href).then(() => views.refresh());
    },
    onChange: () => saver?.schedule(),
  });
  let saver: SessionSaver | undefined;
  // 利用者のキー割り当て(config.json の keybindings)を、標準に重ねる。問題のある設定は、無視して、知らせる
  const config: HostConfig | undefined = await host.getConfig?.().catch(() => undefined);
  const bindings = resolveBindings(config?.keybindings);
  const ctx: AppContext = { host, model, views, echo, minibuffer, bindings };

  const commands = createCommands(ctx);
  const keyboard = installKeyboard(ctx, commands, createKeymap(bindings.bindings));

  const files = await host.listFiles();
  const first = files.includes("index.md") ? "index.md" : files[0];
  const useSession = config?.restoreSession !== false && !!host.saveSession;
  if (useSession && (await restoreSession(ctx, files))) {
    views.refresh();
    echo.message(`${files.length} files / 前回の状態を復元しました`);
  } else if (first) {
    await openAt(ctx, first);
    views.refresh();
    echo.message(`${files.length} files / host: ${host.name}`);
  } else {
    echo.message("Markdown ファイルがありません");
  }
  // 復元の前に保存すると、前回の状態を消してしまう。復元(または、初期表示)のあとに始める
  if (useSession) {
    saver = createSessionSaver(ctx);
    const flushNow = (): void => void saver?.flush();
    window.addEventListener("pagehide", flushNow);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") flushNow();
    });
  }
  wireHostEvents(ctx, commands);
  if (bindings.problems.length) {
    echo.message(`設定: ${bindings.problems.length} 件の問題があります(C-h b で確認できます)`);
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
