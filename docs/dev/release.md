# リリースの手順

署名・公証・配布の手順。`scripts/release.sh` が、Developer ID 署名 → 公証 → ステープル → `.zip` / `.dmg` → チェックサムまでを行う。成果物の内容と署名の設計は [distribution.md](distribution.md)。

## 1. 前提(1 回だけ)

1. **署名の証明書:** キーチェーンに「Developer ID Application: …」がある(Apple Developer Program の証明書。`security find-identity -v -p codesigning` で確認する)。複数あるときは、`HYPERBUF_SIGN_IDENTITY` で指定する。
2. **公証の認証情報:** Apple ID の **App 用パスワード**(appleid.apple.com で発行)を、キーチェーンのプロファイルとして保存する。**このスクリプトも Claude も、パスワードや Apple ID を受け取らない**。自分の端末で、1 回だけ実行する。

   ```bash
   xcrun notarytool store-credentials "hyperbuf-notary" --apple-id "<Apple ID>" --team-id "<チーム ID>"
   ```

   パスワードは、コマンドが対話で尋ねる。`--password` を引数に書かない(履歴に残るため)。

## 2. リリースの手順

1. **バージョンを決める。** 次の 3 か所を、同じ版にそろえる。
   - `app/macos/Sources/HyperBufKit/Version.swift` の `hyperBufVersion`(アプリの版の正)
   - `cli/Sources/HyperBufCLI/CLI.swift` の `cliVersion`
   - `core/package.json` と `protocol/package.json` の `version`

   `Info.plist` の版は、`make-app.sh` が `Version.swift` から設定する(ビルド番号はコミット数)。そろっているかは `scripts/check.sh version` が検査する(`release.sh` も、実行の中で検査する)。

2. **変更履歴を確定する。** `CHANGELOG.md` の `[Unreleased]` を、版の見出し(`## [x.y.z] - 日付`)にし、新しい空の `[Unreleased]` を先頭に置く。
3. **ブランチで準備して、マージする。** 版と変更履歴の更新は、`chore/release-<版>` のブランチで行い、`--no-ff` で `main` にマージする(ブランチ運用: `CLAUDE.md`)。以降は、マージ後の `main` で作業する。
4. **チェック。** `scripts/check.sh` が通ること。GUI の統合テスト(`scripts/integration-test*.sh`。CI では実行しない)も通ること。
5. **リハーサル**(任意。公証しない)。`scripts/release.sh --dry-run`。組み立て・ad-hoc 署名・`.zip` / `.dmg` の作成だけを試す。**この成果物は、配布しない**。
6. **本番。**

   ```bash
   HYPERBUF_NOTARY_PROFILE=hyperbuf-notary scripts/release.sh
   ```

   成果物は `dist/release/`(`HyperBuf-<版>.zip`、`HyperBuf-<版>.dmg`、`SHA256SUMS`)。署名の際に、キーチェーンへのアクセスの許可を尋ねられることがある。

7. **配布の前の確認。** §3「まっさらな Mac での確認」。
8. **公開。** §4。

## 3. まっさらな Mac での確認(配布の前)

公証の結果は、実際に、別の Mac(または、新しいユーザー)で確かめる。**Intel の Mac でも確かめる**(Universal の x86_64 の部分は、開発機で実行できないことがある)。

1. `.dmg` を、ブラウザや AirDrop など**隔離属性(quarantine)が付く経路**で渡す。手元で再現するなら、`xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" <ファイル>`。
2. `.dmg` を開き、`HyperBuf.app` を `/Applications` にドラッグして起動する。**Gatekeeper の警告が出ない**こと(「開発元を確認できません」が出たら失敗)。
3. `spctl -a -vv -t exec /Applications/HyperBuf.app` が `accepted`、`source=Notarized Developer ID` になること。`codesign --verify --deep --strict` が通ること。
4. 起動して、文書を開き、Mermaid・数式・コードブロックが描画されること。`hyperbuf` CLI(`Resources/bin/hyperbuf`)から、ファイルを開けること。外部通信がないこと(Little Snitch などで確認すると確実)。
5. 初回起動の確認のダイアログ(「インターネットからダウンロードされたアプリ」)は、公証済みなら、正常に出てよい。

## 4. 公開(GitHub Releases)

**想定する手順(まだ実行したことがなく、未検証)。** ソースの公開と GitHub Releases への公開は、M8 の残りの作業である([migration-plan.md](../history/migration-plan.md))。公開前は、成果物を非公開の共有(関係者への配布)で渡す。

1. 本番のビルドを作った `main` のコミットに、タグ(`v<版>`)を付けて、push する。

   ```bash
   git tag -a v<版> -m "HyperBuf <版>"
   git push origin v<版>
   ```

2. GitHub Releases に、成果物と `SHA256SUMS` をアップロードする。リリースノートは、`CHANGELOG.md` の、その版の節を使う。

   ```bash
   awk '/^## \[<版>\]/{f=1;next} /^## \[/{f=0} f' CHANGELOG.md > /tmp/notes.md
   gh release create v<版> dist/release/HyperBuf-<版>.zip dist/release/HyperBuf-<版>.dmg dist/release/SHA256SUMS \
     --title "HyperBuf <版>" --notes-file /tmp/notes.md
   ```

3. ダウンロードした `.dmg` が、`SHA256SUMS` と一致し、§3 の確認を通ること。

## 5. 未決事項

リリースの手順に影響するもの。ほかの配布の残りの作業(Homebrew cask、ソースの公開に向けた整備など)は、[migration-plan.md](../history/migration-plan.md) の M8。

- **リリースの自動化(GitHub Actions)。** 署名の秘密を CI に置くかどうかの判断が要るため、手動のリリースから始めている。
- **自動更新(Sparkle など)。** 外部通信を伴うため、「Local first」の方針との調整が要る。当面は、なし。
