/**
 * シェル(macOS アプリなど)と Web コアの境界。シェルは `window.hyperbufHost` として注入する。
 * Web コアは、これ以外の方法でシェルの機能を使わない。
 * 契約の詳細: docs/integration-protocol.md、docs/poc-navigation-results.md
 */
import type { SourceLocation } from "./locate.ts";

/** `markLocation` の結果。 */
export interface MarkResult {
  ok: boolean;
  /** エディタを呼び出したか(設定されたコマンドを実行したか)。 */
  triggered: boolean;
  /** 利用者に見せる説明。 */
  message: string;
}

/** 利用者の設定(config.json)のうち、Web コアが使うもの。 */
export interface HostConfig {
  /** キー列 → コマンド名(`null` は、標準の割り当てを外す)。 */
  keybindings?: Record<string, string | null>;
  /** 前回の状態(window の配置・履歴・閲覧位置)を復元し、保存するか(既定は true)。 */
  restoreSession?: boolean;
  /** シェルが見つけた設定の問題(許可パス / 警告パスなど)。`C-h b` の「設定の問題」に出す。 */
  problems?: string[];
}

/** ディレクトリの 1 階層分の一覧の 1 件(`.md` のファイルとサブディレクトリだけ)。 */
export interface DirEntry {
  name: string;
  dir: boolean;
}

export interface DirectoryListing {
  entries: DirEntry[];
  /** 件数の上限で打ち切った。 */
  truncated: boolean;
  /** 読めなかった・存在しないときの理由。 */
  error?: string;
}

/** ディレクトリ以下の `.md` を再帰でたどった一覧(`C-x p f`)。 */
export interface TreeListing {
  /** 起点からの相対パス(昇順)。 */
  files: string[];
  /** ファイル数・時間の上限で打ち切った。 */
  truncated: boolean;
  /** 再帰しなかった理由(起点が `~` や `/` のとき、など)。 */
  refused?: string;
  error?: string;
}

/**
 * ファイルへのアクセスの判定(docs/project-model.md §5)。
 *  - allow: そのまま読める
 *  - confirm: 警告パスのファイル。利用者の確認が要る(承認されたら `remember` のパスを記憶する)
 */
export type Access = { access: "allow" } | { access: "confirm"; remember: string };

export interface HyperbufHost {
  /** 利用者のホストディレクトリ(絶対パス)。`~` の展開と、表示の短縮に使う。 */
  readonly home: string;
  /**
   * このフレームの、前回のセッション(`SessionSnapshot`)。なければ null。
   * 内容は信頼しない(Web コアが検証する)。保存先はシェルが決める。
   */
  loadSession?(): Promise<unknown>;
  /** セッションを保存する。シェルは、大きさを制限する。 */
  saveSession?(snapshot: unknown): Promise<void>;
  /** 利用者の設定。なければ、標準のまま。 */
  getConfig?(): Promise<HostConfig>;
  /** シェルの識別名(診断用)。 */
  readonly name: string;
  /** ディレクトリの 1 階層(隠しファイルは、`hidden` のときだけ含める)。入力欄の補完に使う。 */
  listDirectory(dir: string, options?: { hidden?: boolean }): Promise<DirectoryListing>;
  /** ディレクトリ以下の `.md` の再帰の一覧(隠しファイルと node_modules を除く)。守りはシェルが行う。 */
  listTree(dir: string): Promise<TreeListing>;
  /**
   * Markdown を読む(絶対パス、`.md` のみ)。アクセスの判定はしない
   * (利用者が打った・選んだパス、判定済みの外部要求、復元されたセッション)。
   */
  readFile(path: string): Promise<string>;
  /** リンクやリソースが指すファイルの判定。警告パスなら、確認が要る。 */
  checkAccess?(paths: string[]): Promise<Access[]>;
  /** 確認を承認した: `remember` のパスを、記憶する(永続化)。シェルが提案したものだけが記憶される。 */
  allow?(remember: string): Promise<boolean>;
  /** 記憶したパスの一覧と、取り消し(`forget-remembered-path`)。 */
  listRemembered?(): Promise<string[]>;
  forget?(path: string): Promise<boolean>;
  /** フレーム(macOS のウィンドウ)の操作(`C-x 5 …`)。 */
  frame?(action: "make" | "delete" | "other" | "delete-others"): Promise<void>;
  /** 表示中のファイル(絶対パス)の一覧。シェルは、これだけを監視する。 */
  watch?(paths: string[]): void;
  /** 表示中のファイルの変更(`changed`)・削除(`deleted`)の通知。 */
  onFileChanged(callback: (path: string, state: "changed" | "deleted") => void): void;
  /** 文書から参照されるローカル画像の URL(絶対パス → 読み込める URL)。判定はシェルが、読み込み時に行う。 */
  resolveResource?(path: string): string;
  /** `dir` 以下の全文検索。エンジンはシェルが選ぶ。結果のパスは絶対パス。 */
  search?(dir: string, query: string, options?: SearchOptions): Promise<SearchResult>;
  /** 外部(CLI・Emacs 連携)からの「開く」要求。 */
  onOpen?(callback: (request: OpenRequest) => void): void;
  /** 「開く」要求が期限切れなどで取り消された(確認待ちのミニバッファを閉じる)。 */
  onOpenCancel?(callback: (id: string) => void): void;
  /**
   * ビューアで指した場所(元の位置)を、エディタ連携のために記録する(「Emacs で編集」)。
   * シェルが、ファイルの識別情報(ハッシュ等)を添えて保持し、エディタが `get-location` で取りに来る。
   * 設定されていれば、シェルが、利用者の設定した固定のコマンドで、エディタを呼び出す。
   */
  markLocation?(location: SourceLocation): Promise<MarkResult>;
  /** シェルから、「エディタで編集」の操作(右クリックメニューなど)が選ばれた。 */
  onEdit?(callback: () => void): void;
  /** 位置の問い合わせ(`get-view`: いまの表示)への応答を登録する。 */
  onQuery?(callback: (op: string) => Promise<unknown>): void;
  /** 「開く」要求への結果を返す(確認待ちを含む)。 */
  respond?(id: string, result: unknown): void;
  /**
   * 警告パスのファイルを開く要求を、利用者が承認(または拒否)した。
   * 承認されると、シェルが提案したパス(`OpenRequest.remember`)が記憶される。
   * Web 側から、任意のパスを記憶させることはできない(承認できるのは、シェルが提案した要求の id だけ)。
   * @returns 承認が受理されたか(受理されれば、読める)
   */
  confirmOpen?(id: string, accepted: boolean): Promise<boolean>;
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
  /** 検索しなかった理由(起点が `~` や `/` のとき、など)。 */
  refused?: string;
  error?: string;
}

export interface OpenRequest {
  id?: string;
  /** 絶対パス。 */
  path: string;
  /** 警告パスのファイルで、確認が要る。 */
  confirm?: boolean;
  /** 確認が承認されたら記憶するパス(シェルが提案する)。 */
  remember?: string;
  line?: number;
  anchor?: string;
  error?: string;
}
