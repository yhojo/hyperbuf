// 開発用ホスト: 開発サーバー(scripts/dev-server.mjs)の HTTP API を使う。
// 本番では、シェル(macOS アプリなど)が `window.hyperbufHost` を注入するので、使われない。

import type {
  DirectoryListing,
  HostConfig,
  HyperbufHost,
  SearchOptions,
  SearchResult,
  TreeListing,
} from "./host.ts";

export async function createDevHost(base = ""): Promise<HyperbufHost> {
  const api = (path: string): string => `${base}/__project/${path}`;
  const json = async <T>(url: string): Promise<T> => (await (await fetch(url)).json()) as T;
  const { home } = await json<{ home: string }>(api("info"));
  const listeners: ((path: string, state: "changed" | "deleted") => void)[] = [];
  let events: EventSource | null = null;

  return {
    name: "dev-server",
    home,
    async listDirectory(dir, options) {
      return json<DirectoryListing>(
        api(`dir?path=${encodeURIComponent(dir)}&hidden=${options?.hidden ? 1 : 0}`),
      );
    },
    async listTree(dir) {
      return json<TreeListing>(api(`tree?path=${encodeURIComponent(dir)}`));
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
          const { path, state } = JSON.parse(e.data) as {
            path: string;
            state: "changed" | "deleted";
          };
          for (const l of listeners) l(path, state);
        };
      }
    },
    resolveResource: (path) => api(`raw/${path.split("/").map(encodeURIComponent).join("/")}`),
    async search(dir: string, query: string, options: SearchOptions = {}) {
      return json<SearchResult>(
        api(
          `search?dir=${encodeURIComponent(dir)}&q=${encodeURIComponent(query)}&limit=${options.limit ?? 200}`,
        ),
      );
    },
  };
}
