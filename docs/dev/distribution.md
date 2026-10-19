# 配布物の仕様

HyperBuf の配布物(`.app`、`.zip`、`.dmg`)が何を含み、どう署名されているか。作り方と手順は [release.md](release.md)。経緯と調査の記録は [distribution-decisions.md](../history/distribution-decisions.md)。

## 1. 配布の方式

- オープンソース(GitHub)と、**Developer ID 署名 + 公証**の直接配布。**Mac App Store は対象外**。
- **サンドボックスなし**で設計する(ソケット、外部コマンドの実行、任意のディレクトリの読み取りを、制約なく扱うため)。権限の明示と最小化という方針は変わらない。
- Bundle ID は `com.yhojo.hyperbuf`。最低の macOS は 14。

## 2. 成果物

`scripts/release.sh` が `dist/release/` に作る(置き場所は `HYPERBUF_RELEASE_DIR` で変える)。`<版>` は `app/macos/Sources/HyperBufKit/Version.swift` の `hyperBufVersion`。

| ファイル            | 内容                                                                                            |
| ------------------- | ----------------------------------------------------------------------------------------------- |
| `HyperBuf-<版>.zip` | `HyperBuf.app`(署名・公証・ステープル済み)                                                      |
| `HyperBuf-<版>.dmg` | `HyperBuf.app` と案内、ライセンス、Emacs 連携を含むディスクイメージ(署名・公証・ステープル済み) |
| `SHA256SUMS`        | 上の 2 つのチェックサム                                                                         |

## 3. 対応するアーキテクチャ

release ビルドは **Universal(arm64 と x86_64)**。Apple Silicon と Intel の Mac の両方で動く(`make-app.sh` が `swift build --arch arm64 --arch x86_64` でビルドする)。

- **最低の macOS は 14。** macOS 13 以前は対象外で、Intel の Mac のうち、macOS 14 に更新できないもの(2017 年の MacBook Pro など)も対象外となる。
- 配布物が Universal かは、`lipo -archs HyperBuf.app/Contents/MacOS/HyperBuf` が `x86_64 arm64` を示すこと、同梱の CLI(`Contents/Resources/bin/hyperbuf`)も同様であることで確かめる。
- 開発機が Apple Silicon で Rosetta がないと、x86_64 の部分は実行できない。**Intel の Mac での起動確認は、配布の前に行う**([release.md](release.md) の「まっさらな Mac での確認」)。
- macOS 27 以降の SDK は、x86_64 を非推奨とする警告を出す。Apple が Intel の Mac のサポートを終えていくため、いずれ arm64 だけに戻す予定。

## 4. 同梱するもの

### 4.1 `HyperBuf.app` の中

- `Contents/Resources/bin/hyperbuf`: CLI。`PATH` に通すには、シンボリックリンクを張る(Homebrew cask の `binary` でも張れる)。アプリの実行ファイル(`HyperBuf`)と、大文字小文字を区別しないファイルシステムで衝突しないよう、`MacOS/` ではなく `Resources/bin/` に置く。
- `LICENSE.txt`、`NOTICE.txt`、`THIRD-PARTY-NOTICES.txt`: サードパーティの著作権表示とライセンスを含む。アプリメニューの `Show Third-Party Licenses` で開く。`THIRD-PARTY-NOTICES.txt` は `make-app.sh` が `core/scripts/licenses.mjs` で生成する(一覧: [third-party-licenses.md](../user/third-party-licenses.md))。
- Web コア(`Contents/Resources/web`): `core/dist`。

### 4.2 `.dmg` の中

- `HyperBuf.app` と、`/Applications` へのリンク。
- `LICENSE.txt`、`NOTICE.txt`、`CHANGELOG.md`(利用者が更新内容を確認できる)。
- `README.md`: 利用者向けの案内。元は [getting-started.md](../user/getting-started.md)(概要、インストール、基本の操作、設定、`hyperbuf` コマンドのリンクの作り方、Emacs 連携)で、`release.sh` が `README.md` としてコピーする。単独で読めるよう、相対リンクは使わない。
- `emacs/`: `hyperbuf.el`、`README.md`、`LICENSE`。`emacs/` は GPL-3.0-or-later で、アプリ(Apache-2.0)とは別のプログラムとして、自身のライセンスを添えて同梱する(集積であり、結合ではない)。

## 5. 署名の設計

- **Hardened Runtime**(`--options runtime`)と**セキュアタイムスタンプ**(`--timestamp`)。公証の要件。
- **エンタイトルメントは付けない。** WebKit のレンダリング(JIT など)は、Apple の WebContent プロセスが行うため、アプリ本体に JIT の許可は要らない。外部コマンド(エディタの呼び出し)の実行、ソケット、ファイルの読み取りは、Hardened Runtime でも制限されない(サンドボックスなし)。
- 署名の順は、内側(CLI)→ 外側(アプリ)。`--deep` は使わない。`.dmg` にも署名する。
- 公証は、アプリ(`.zip` にして提出)と `.dmg` のそれぞれに行い、結果をステープルする。
- 公証の認証情報は、キーチェーンのプロファイルとして保存したものだけを使う。スクリプトは、Apple ID、パスワード、API キーを受け取らない([release.md](release.md))。

## 6. ビルドの再現性と情報の漏えい対策

- release ビルドは、`-file-prefix-map` で、ソースの絶対パス(`/Users/…`)を `/hyperbuf` に置き換える(`make-app.sh`)。実行ファイルに、ビルドしたマシンのパスを残さない。
- Web のバンドルとリソースに、個人のパス・秘密情報・ソースマップを含めない。
- Bundle ID は、意図した公開の識別子である。

## 7. アイコン

- **既定のアイコン:** 「H」。`app/macos/Resources/AppIcon.icns`(確認用に `AppIcon-1024.png`)。HyperBuf の頭文字であり、作者の姓の頭文字でもある。
- **元の画像:** `app/macos/Resources/source/hyperbuf-icon-original.icns`。暗い角丸の板が画像いっぱいに広がっていて、角の外側に地の色が焼き込まれ、透明な余白がない。macOS のアイコンは、透明な余白がないと、Dock や Finder で、他のアプリより大きく、角に四角い地が見える。
- **既定のアイコンの作り方:**

  ```bash
  swift app/macos/scripts/icon-from-image.swift app/macos/Resources/source/hyperbuf-icon-original.icns app/macos/Resources
  ```

  元の画像から、角の外側は透明、周囲に約 10% の余白、影つきの、標準のアイコンを作る(デザインは変えない)。結果(`AppIcon.icns`、`AppIcon-1024.png`)は、リポジトリに置く。

- **代替のデザイン:** `app/macos/Resources/alternatives/split-windows/`(分割した 2 つの window)。`swift app/macos/scripts/make-icon.swift` が、コードから生成する。既定にはしていない。
- **差し替え:** `HYPERBUF_ICON=<.icns のパス>` を指定して、`make-app.sh` または `release.sh` を実行する。成果物の置き場所を分けるなら、`HYPERBUF_RELEASE_DIR` も指定する。
- アイコンの著作物は、リポジトリのほかの部分と同じく、Apache-2.0 で提供する(`LICENSE`)。ただし、商標(名前・ロゴとしての利用)は許諾しない(Apache-2.0 §6)。

## 8. 環境変数

ビルド・リリースのスクリプトが読む環境変数(`HYPERBUF_ICON`、`HYPERBUF_SIGN_IDENTITY`、`HYPERBUF_NOTARY_PROFILE`、`HYPERBUF_RELEASE_DIR`)は、[debug-environment.md](debug-environment.md) §3。
