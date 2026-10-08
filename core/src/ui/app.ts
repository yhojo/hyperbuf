// アプリの組み立て。状態(model)、部品(エコー・ミニバッファ・描画)、コマンド、キー入力、
// ホストからのイベントを結びつける。

import type { HyperbufHost } from "../host.ts";
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
import { defaultKeymap } from "./keymap.ts";
import { createMinibuffer } from "./minibuffer.ts";
import { follow, openAt } from "./navigation.ts";
import { searchProject } from "./search.ts";
import { Views } from "./windows.ts";

export interface AppHandle {
  ctx: AppContext;
  commands: Commands;
  keyboard: KeyboardHandle;
  /** 選択中の window で文書を開き、描画する(外部連携・テスト用)。 */
  open(path: string, anchor?: string | null): Promise<void>;
  search(query: string): Promise<void>;
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
  });
  const ctx: AppContext = { host, model, views, echo, minibuffer };

  const commands = createCommands(ctx);
  const keyboard = installKeyboard(ctx, commands, defaultKeymap());

  const files = await host.listFiles();
  const first = files.includes("index.md") ? "index.md" : files[0];
  if (first) {
    await openAt(ctx, first);
    views.refresh();
    echo.message(`${files.length} files / host: ${host.name}`);
  } else {
    echo.message("Markdown ファイルがありません");
  }
  wireHostEvents(ctx);

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
  };
}
