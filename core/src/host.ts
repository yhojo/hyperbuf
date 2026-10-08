/**
 * シェル(macOS アプリなど)と Web コアの境界。シェルは `window.hyperbufHost` として注入する。
 * Web コアは、これ以外の方法でシェルの機能を使わない。
 * 契約の詳細: docs/integration-protocol.md、docs/poc-navigation-results.md
 */
export interface HyperbufHost {
  /** シェルの識別名(診断用)。 */
  readonly name: string;
  /** プロジェクト内の Markdown の相対パス(隠しファイルと node_modules を除く)。 */
  listFiles(): Promise<string[]>;
  /** プロジェクト内の Markdown を読む。範囲外・`.md` 以外は拒否される。 */
  readFile(path: string): Promise<string>;
  /** ファイルの変更・作成・削除の通知(相対パス)。 */
  onFileChanged(callback: (path: string) => void): void;
  /** 文書から参照されるローカル画像の URL(相対パス → 読み込める URL)。 */
  resolveResource?(path: string): string;
  /** プロジェクト内の全文検索。エンジンはシェルが選ぶ。 */
  search?(query: string, options?: SearchOptions): Promise<SearchResult>;
  /** 外部(CLI・Emacs 連携)からの「開く」要求。 */
  onOpen?(callback: (request: OpenRequest) => void): void;
  /** 位置の問い合わせ(`get-location`)への応答を登録する。 */
  onQuery?(callback: (op: string) => Promise<unknown>): void;
  /** 「開く」要求への結果を返す(確認待ちを含む)。 */
  respond?(id: string, result: unknown): void;
  /** Web コアの準備ができた合図。これ以前に届いた要求は、この後に渡される。 */
  ready?(): void;
  /** 診断ログ(開発用)。 */
  log?(text: string): void;
}

export interface SearchOptions {
  limit?: number;
  engine?: string;
}

export interface SearchHit {
  path: string;
  line: number;
  text: string;
}

export interface SearchResult {
  results: SearchHit[];
  total: number;
  truncated: boolean;
  error?: string;
}

export interface OpenRequest {
  id?: string;
  /** プロジェクト内なら相対パス、範囲外なら絶対パス(`outside` が真)。 */
  path: string;
  line?: number;
  anchor?: string;
  outside?: boolean;
  error?: string;
}
