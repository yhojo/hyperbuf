// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

import type { HyperbufHost } from "../host.ts";
import type { BindingsResult } from "../keybindings.ts";
import type { Model } from "../model.ts";
import type { Echo } from "./echo.ts";
import type { Minibuffer } from "./minibuffer.ts";
import type { Views } from "./windows.ts";

/** App state and components shared by each part of the UI. */
export interface AppContext {
  host: HyperbufHost;
  model: Model;
  views: Views;
  echo: Echo;
  minibuffer: Minibuffer;
  /** Current key bindings and config problems (defaults + user settings). Used by describe-bindings. */
  bindings: BindingsResult;
  /** Config problems found by the shell (allow paths / warn paths, etc.). */
  problems: readonly string[];
}
