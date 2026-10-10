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

## 同梱するもの

- `HyperBuf.app/Contents/Resources/bin/hyperbuf`: CLI(`PATH` に通すには、シンボリックリンクを張る。Homebrew cask の `binary` でも張れる)。アプリの実行ファイル(`HyperBuf`)と、大文字小文字を区別しないファイルシステムで衝突しないよう、`MacOS/` ではなく `Resources/bin/` に置く。
- `LICENSE.txt`、`NOTICE.txt`、`THIRD-PARTY-NOTICES.txt`(サードパーティの著作権表示とライセンス。メニューの「サードパーティのライセンスを表示」で開く)。
- `.dmg` には、`LICENSE.txt` と `NOTICE.txt` も入る。

## 署名の設計

- **Hardened Runtime**(`--options runtime`)と**セキュアタイムスタンプ**(`--timestamp`)。公証の要件。
- **エンタイトルメントは付けない**。WebKit のレンダリング(JIT など)は、Apple の WebContent プロセスが行うため、アプリ本体に JIT の許可は要らない。外部コマンド(エディタの呼び出し)の実行、ソケット、ファイルの読み取りは、Hardened Runtime でも制限されない(サンドボックスなし)。ad-hoc 署名の Hardened Runtime で、画面の表示・ソケット・CLI が動くことを確認済み(2026-10-10)。
- 署名の順は、内側(CLI)→ 外側(アプリ)。`--deep` は使わない。

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
