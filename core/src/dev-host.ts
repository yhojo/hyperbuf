// 開発用ホスト: 開発サーバー(scripts/dev-server.mjs)の HTTP API を使う。
// 本番では、シェル(macOS アプリなど)が `window.hyperbufHost` を注入するので、使われない。

import type { HostConfig, HyperbufHost, SearchOptions, SearchResult } from "./host.ts";

export function createDevHost(base = ""): HyperbufHost {
  const api = (path: string): string => `${base}/__project/${path}`;
  const listeners: ((path: string) => void)[] = [];
  let events: EventSource | null = null;

  return {
    name: "dev-server",
    async listFiles() {
      return (await (await fetch(api("files"))).json()) as string[];
    },
    async getConfig() {
      const res = await fetch(api("config"));
      return res.ok ? ((await res.json()) as HostConfig) : {};
    },
    async readFile(path) {
      const res = await fetch(api(`file?path=${encodeURIComponent(path)}`));
      if (!res.ok) throw new Error(`${path}: ${res.status}`);
      return res.text();
    },
    onFileChanged(callback) {
      listeners.push(callback);
      if (!events) {
        events = new EventSource(api("events"));
        events.onmessage = (e: MessageEvent<string>) => {
          for (const l of listeners) l(e.data);
        };
      }
    },
    resolveResource: (path) => api(`raw/${path.split("/").map(encodeURIComponent).join("/")}`),
    async search(query: string, options: SearchOptions = {}) {
      const res = await fetch(
        api(`search?q=${encodeURIComponent(query)}&limit=${options.limit ?? 200}`),
      );
      return (await res.json()) as SearchResult;
    },
  };
}
