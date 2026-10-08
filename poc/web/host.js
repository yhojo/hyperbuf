// シェルとの境界。シェルは window.hyperbufHost を注入する。無ければ HTTP 経由の開発用ホストを使う。
//
// host = {
//   name: string,
//   listFiles(): Promise<string[]>        プロジェクト内の Markdown の相対パス
//   readFile(path): Promise<string>
//   onFileChanged(cb: (path) => void)     外部更新の通知
//   resolveResource?(path): string        文書から参照されるローカル画像の URL(相対パス → 読み込める URL)
//   simulateChange?(path): Promise<void>  開発用: 外部更新の模擬
// }

export function getHost() {
  return window.hyperbufHost ?? createFetchHost();
}

function createFetchHost(base = new URL("../sample/", import.meta.url)) {
  const overrides = new Map();
  const listeners = [];
  return {
    name: "fetch (dev)",
    async listFiles() {
      return (await fetch(new URL("manifest.json", base))).json();
    },
    async readFile(path) {
      if (overrides.has(path)) return overrides.get(path);
      const res = await fetch(new URL(path, base));
      if (!res.ok) throw new Error(`${path}: ${res.status}`);
      return res.text();
    },
    onFileChanged(cb) {
      listeners.push(cb);
    },
    resolveResource: (path) => new URL(path, base).href,
    async simulateChange(path) {
      const text = overrides.get(path) ?? (await (await fetch(new URL(path, base))).text());
      overrides.set(path, `${text}\n\n- 外部更新 ${new Date().toLocaleTimeString()}\n`);
      listeners.forEach((cb) => cb(path));
    },
  };
}
