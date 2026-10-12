# リリースの手順(署名・公証・配布)

`scripts/release.sh` が、Developer ID 署名 → 公証 → ステープル → `.zip` / `.dmg` → チェックサムまでを行う。配布は、GitHub Releases などへのアップロード(直接配布。Mac App Store は対象外、サンドボックスなし)。

## 前提(1 回だけ)

1. **署名の証明書**: キーチェーンに「Developer ID Application: …」がある(Apple Developer Program の証明書。`security find-identity -v -p codesigning` で確認する)。複数あるときは、`HYPERBUF_SIGN_IDENTITY` で指定する。
2. **公証の認証情報**: Apple ID の **App 用パスワード**(appleid.apple.com で発行)を、キーチェーンのプロファイルとして保存する。**このスクリプトも Claude も、パスワードや Apple ID を受け取らない**。自分の端末で、1 回だけ実行する。

   ```bash
   xcrun notarytool store-credentials "hyperbuf-notary" --apple-id "<Apple ID>" --team-id "<チーム ID>"
   ```

   (パスワードは、コマンドが対話で尋ねる。`--password` を引数に書かない。履歴に残るため。)

## リリースの手順

1. **バージョンを決める**: `app/macos/Sources/HyperBufKit/Version.swift` の `hyperBufVersion`(アプリの版の正)と、CLI の `cliVersion`(`cli/Sources/HyperBufCLI/CLI.swift`)を、そろえて更新する。`Info.plist` の版は、`make-app.sh` が `Version.swift` から設定する(ビルド番号はコミット数)。
2. **チェック**: `scripts/check.sh` が通ること。GUI の統合テスト(`scripts/integration-test*.sh`)も通ること。
3. **リハーサル**(任意。公証しない): `scripts/release.sh --dry-run`。組み立て・ad-hoc 署名・`.zip` / `.dmg` の作成だけを試す。**この成果物は、配布しない**。
4. **本番**:

   ```bash
   HYPERBUF_NOTARY_PROFILE=hyperbuf-notary scripts/release.sh
   ```

   成果物は `dist/release/`(`HyperBuf-<版>.zip`、`HyperBuf-<版>.dmg`、`SHA256SUMS`)。署名の際に、キーチェーンへのアクセスの許可を尋ねられることがある。

5. **配布の前の確認**(下の「まっさらな Mac での確認」)。
6. **公開**: タグ(`v<版>`)を付け、GitHub Releases に成果物と `SHA256SUMS` をアップロードする(ソースの公開前は、非公開の共有でもよい)。

## 対応するアーキテクチャ

release ビルドは **Universal(arm64 と x86_64)**。Apple Silicon と、Intel の Mac(2018 年の Mac mini など)の両方で動く(`make-app.sh` が `swift build --arch arm64 --arch x86_64` でビルドする)。最低の macOS は 14。

- 2026-10-11: 最初のリリースのビルドは arm64 だけで、Intel の Mac(macOS 15.8.1)で「このOSに対応していない」と表示された。Universal に直した。
- **最低の macOS は 14**(macOS 13 は対象外。判断の経緯は `docs/migration-plan.md`)。Intel の Mac のうち、macOS 14 に更新できないもの(2017 年の MacBook Pro など)は、対象外。
- 開発機が Apple Silicon で Rosetta がないと、x86_64 の部分は実行できない。**Intel の Mac での起動確認は、配布の前に必ず行う**(下の「まっさらな Mac での確認」)。
- 配布物が Universal かは、`lipo -archs HyperBuf.app/Contents/MacOS/HyperBuf`(`x86_64 arm64`)と、同梱の `Contents/Resources/bin/hyperbuf` で確認できる。
- macOS 27 以降の SDK は、x86_64 を非推奨とする警告を出す。Apple は Intel の Mac のサポートを終えていくため、いずれ arm64 だけに戻す。

## アイコン

- **既定のアイコン: 「H」**(`app/macos/Resources/AppIcon.icns`、確認用に `AppIcon-1024.png`)。暗い板の上に、半透明のタイルで「H」を描いたデザイン(Yasuo Hojo の作。HyperBuf の頭文字であり、作者の姓の頭文字でもある)。2026-10-12 に決定した(知り合いへの見せ合いで、「目立つ」「H が分かりやすい」という評価)。
- **元の画像**: `app/macos/Resources/source/hyperbuf-icon-original.icns`。暗い角丸の板が画像いっぱいに広がっていて、角の外側に地の色が焼き込まれ、透明な余白がない。macOS のアイコンは、透明な余白がないと、Dock や Finder で、他のアプリより大きく、角に四角い地が見える。
- **既定のアイコンの作り方**: `swift app/macos/scripts/icon-from-image.swift app/macos/Resources/source/hyperbuf-icon-original.icns app/macos/Resources`。元の画像から、角の外側は透明、周囲に約 10% の余白、影つきの、標準のアイコンを作る(デザインは変えない)。結果(`AppIcon.icns`、`AppIcon-1024.png`)は、リポジトリに置く。
- **代替のデザイン**: `app/macos/Resources/alternatives/split-windows/`(分割した 2 つの window。`swift app/macos/scripts/make-icon.swift` が、コードから生成する)。視認性の評価が分かれたため、既定にしなかった。
- **別のアイコンに差し替える**(見比べ・別のデザイン): `HYPERBUF_ICON=<.icns のパス>` を指定して、`make-app.sh` または `release.sh` を実行する。成果物の置き場所を分けるなら、`HYPERBUF_RELEASE_DIR` も指定する。
- アイコンの著作物は、リポジトリのほかの部分と同じく、Apache-2.0 で提供する(`LICENSE`)。ただし、商標(名前・ロゴとしての利用)は許諾しない(Apache-2.0 §6)。

## 同梱するもの

- `HyperBuf.app/Contents/Resources/bin/hyperbuf`: CLI(`PATH` に通すには、シンボリックリンクを張る。Homebrew cask の `binary` でも張れる)。アプリの実行ファイル(`HyperBuf`)と、大文字小文字を区別しないファイルシステムで衝突しないよう、`MacOS/` ではなく `Resources/bin/` に置く。
- `LICENSE.txt`、`NOTICE.txt`、`THIRD-PARTY-NOTICES.txt`(サードパーティの著作権表示とライセンス。メニューの「サードパーティのライセンスを表示」で開く)。
- `.dmg` には、`LICENSE.txt`・`NOTICE.txt` に加えて、配布用の `README.md`(元: `app/macos/Resources/dmg/README.md`。インストール・基本の操作・`hyperbuf` コマンドのリンク・Emacs 連携)と、`emacs/`(`hyperbuf.el`・`README.md`・`LICENSE`)も入る。`emacs/` は GPL-3.0-or-later で、アプリ(Apache-2.0)とは別のプログラムとして、自身のライセンスを添えて同梱する(集積であり、結合ではない)。CLI(`hyperbuf`)は、署名・公証済みの `.app` の中(`Contents/Resources/bin/`)にあり、配布用の README が、リンクの作り方を案内する。

## 署名の設計

- **Hardened Runtime**(`--options runtime`)と**セキュアタイムスタンプ**(`--timestamp`)。公証の要件。
- **エンタイトルメントは付けない**。WebKit のレンダリング(JIT など)は、Apple の WebContent プロセスが行うため、アプリ本体に JIT の許可は要らない。外部コマンド(エディタの呼び出し)の実行、ソケット、ファイルの読み取りは、Hardened Runtime でも制限されない(サンドボックスなし)。ad-hoc 署名の Hardened Runtime で、画面の表示・ソケット・CLI が動くことを確認済み(2026-10-10)。
- 署名の順は、内側(CLI)→ 外側(アプリ)。`--deep` は使わない。

## 同梱物の検査(2026-10-10 に実施)

`strings` で、実行ファイルと同梱物に、個人のパスや秘密情報が残っていないかを調べた。

- 実行ファイルに、ビルドしたマシンのソースの絶対パス(`/Users/…`)が残っていた → release ビルドで、`-file-prefix-map` により `/hyperbuf` に置き換える(`make-app.sh`)。置き換え後は、残っていない。
- Web のバンドルとリソースに、個人のパス・秘密情報・ソースマップはない。Bundle ID(`com.yhojo.hyperbuf`)は、意図した公開の識別子。

## まっさらな Mac での確認(配布の前)

公証の結果は、実際に、別の Mac(または、新しいユーザー)で確かめる。

1. `.dmg` を、ブラウザや AirDrop など**隔離属性(quarantine)が付く経路**で渡す。手元で再現するなら、`xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" <ファイル>`。
2. `.dmg` を開き、`HyperBuf.app` を `/Applications` にドラッグして起動する。**Gatekeeper の警告が出ない**こと(「開発元を確認できません」が出たら失敗)。
3. `spctl -a -vv -t exec /Applications/HyperBuf.app` が `accepted`、`source=Notarized Developer ID` になること。`codesign --verify --deep --strict` が通ること。
4. 起動して、文書を開き、Mermaid・数式・コードブロックが描画されること。`hyperbuf` CLI(`Resources/bin/hyperbuf`)から、ファイルを開けること。外部通信がないこと(Little Snitch などで確認すると確実)。
5. 初回起動の確認のダイアログ(「インターネットからダウンロードされたアプリ」)は、公証済みなら、正常に出てよい。

## まだ決めていないこと

- Homebrew cask(`binary` で CLI も入れる)。公開後の整備。
- リリースの自動化(GitHub Actions)。署名の秘密を CI に置くかどうかの判断が要るため、手動のリリースから始める。
- 自動更新(Sparkle など)。外部通信を伴うため、「Local first」の方針との調整が要る。当面は、なし。
- `hyperbuf` コマンドを `PATH` に通すメニュー(「コマンドラインツールをインストール…」)。
