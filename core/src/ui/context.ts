import type { HyperbufHost } from "../host.ts";
import type { BindingsResult } from "../keybindings.ts";
import type { Model } from "../model.ts";
import type { Echo } from "./echo.ts";
import type { Minibuffer } from "./minibuffer.ts";
import type { Views } from "./windows.ts";

/** UI の各部が共有する、アプリの状態と部品。 */
export interface AppContext {
  host: HyperbufHost;
  model: Model;
  views: Views;
  echo: Echo;
  minibuffer: Minibuffer;
  /** いまのキー割り当てと、設定の問題(標準 + 利用者の設定)。describe-bindings が使う。 */
  bindings: BindingsResult;
}
