# 開発の経緯(docs/history)

プロジェクトの開始から、PoC を経て、リリース段階に至るまでの**記録**。当時の判断と検証を残すもので、**現在の状態に合わせて書き換えない**。現行の設計と仕様は [docs/dev/](../dev/)、利用者向けの説明は [docs/user/](../user/)。

## Summary (English)

This directory holds **records**: what was examined and decided from the start of the project, through the PoCs, to the release stage. The records are written in Japanese, as they were at the time, and are not rewritten to match the present. The current design and specification are in [docs/dev/](../dev/) (English), and the user documentation is in [docs/user/](../user/) (English).

| Document | What it records |
| --- | --- |
| `architecture-evaluation.md` | The architecture evaluation before the PoCs (hypotheses) |
| `poc-interaction-results.md` | Interaction PoC; the choice of SwiftUI + WKWebView for the macOS shell |
| `poc-rendering-results.md` | Rendering PoC; the choice of the rendering stack |
| `poc-navigation-results.md` | Project navigation PoC; search, file watching, virtual buffers |
| `poc-integration-results.md` | Integration PoC; verification and decisions for the integration protocol |
| `poc-frames-results.md` | Memory measurements for multiple frames |
| `license-options.md` | The choice of the license (2026-10-10) |
| `distribution-decisions.md` | Decisions and investigations while preparing distribution (M8) |
| `migration-plan.md` | The plan from the PoCs to the real implementation, and the progress of the milestones (M0 to M8) |
| `plan-change-log.md` | The log of changes to the plans and policies stated in the README |

On 2026-10-19, before the planned publication, the author and committer e-mail address of every commit and tag was replaced by the GitHub noreply address. File contents did not change, but all commit hashes did; the hashes of the PoC branches that appear in these records were updated. The previous history is not published. (The project is finally not made public, because of the result of a trademark check; see `plan-change-log.md`.)

## 履歴の書き換え(2026-10-19)

ソースの公開に先立って、すべてのブランチとタグのコミットについて、作者・コミッターのメールアドレスを GitHub の noreply アドレスに書き換えた。ファイルの内容は変わっていない(各ブランチの先頭のツリーが、書き換えの前後で同じことを確かめた)が、**コミットのハッシュはすべて変わった**。この README と各文書に出る PoC ブランチのコミットハッシュは、書き換え後のものに直してある。書き換えの前の履歴は、公開しない。

## 文書の一覧

| 文書                                                     | 内容                                                             | 現行の仕様                                                                                             |
| -------------------------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| [architecture-evaluation.md](architecture-evaluation.md) | PoC 前のアーキテクチャの評価(仮説の整理)                         | [architecture.md](../dev/architecture.md)                                                              |
| [poc-interaction-results.md](poc-interaction-results.md) | Interaction PoC(2026-10-08)。シェルを SwiftUI + WKWebView に決定 | [interaction-model.md](../dev/interaction-model.md)、[architecture.md](../dev/architecture.md)         |
| [poc-rendering-results.md](poc-rendering-results.md)     | Rendering PoC(2026-10-08)。レンダリング層の構成を決定            | [architecture.md](../dev/architecture.md) §3〜4                                                        |
| [poc-navigation-results.md](poc-navigation-results.md)   | Project navigation PoC(2026-10-08)。検索・監視・仮想 buffer      | [buffer-model.md](../dev/buffer-model.md)、[file-access.md](../dev/file-access.md)                     |
| [poc-integration-results.md](poc-integration-results.md) | Integration PoC(2026-10-08〜09)。連携プロトコルの検証と決定      | [integration-protocol.md](../dev/integration-protocol.md)、[edit-location.md](../dev/edit-location.md) |
| [poc-frames-results.md](poc-frames-results.md)           | 複数フレームのメモリの計測                                       | [buffer-model.md](../dev/buffer-model.md) §7                                                           |
| [license-options.md](license-options.md)                 | ライセンスの選択と決定(2026-10-10)                               | `LICENSE`、`NOTICE`、[third-party-licenses.md](../user/third-party-licenses.md)                        |
| [distribution-decisions.md](distribution-decisions.md)   | 配布の準備(M8)の判断と調査                                       | [distribution.md](../dev/distribution.md)、[release.md](../dev/release.md)                             |
| [migration-plan.md](migration-plan.md)                   | PoC から本実装への移行計画と、マイルストーン(M0〜M8)の進捗       | (M8 の進捗が変わるときに更新する)                                                                      |
| [plan-change-log.md](plan-change-log.md)                 | README の方針・計画の変更の記録                                  |                                                                                                        |

## 旧い文書名・節番号の対応表

history の文書には、当時の文書名と節番号への参照が残っている。次の表で、現行の場所に読み替える。

### 文書の場所の変更

`docs/` 直下にあった文書は、次のように分けた。

| 当時                                                                                                                   | 現在                                                       |
| ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `docs/keybindings.md`、`configuration.md`、`syntax-highlighting.md`、`third-party-licenses.md`                         | `docs/user/`                                               |
| `docs/interaction-model.md`、`integration-protocol.md`、`session-restore.md`、`release.md`                             | `docs/dev/`                                                |
| `docs/architecture-evaluation.md`、`license-options.md`、`migration-plan.md`、`plan-change-log.md`、`poc-*-results.md` | `docs/history/`                                            |
| `app/macos/Resources/dmg/README.md`(`.dmg` に同梱する README)                                                          | [docs/user/getting-started.md](../user/getting-started.md) |

### `docs/project-model.md`(プロジェクトを持たない設計)

バッファを中心に書き直し、アクセス判定を別の文書に分けた。

| 当時の節                                    | 現在                                                                                                          |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| §1 方針、§2 基準のディレクトリ              | [buffer-model.md](../dev/buffer-model.md) §1、§4                                                              |
| §3 ファイルを開く(§3.1 ディレクトリ)        | [buffer-model.md](../dev/buffer-model.md) §5(§5.1)                                                            |
| §4 再帰の一覧と検索                         | [buffer-model.md](../dev/buffer-model.md) §6.1                                                                |
| §5 アクセスの判定、§6 設定                  | [file-access.md](../dev/file-access.md)(§5.1・§5.2 → §2、§5.3 → §3、§5.4 → §4、§5.5 → §5、§5.6 → §6、§6 → §7) |
| §7 セッションと起動、§10.1 セッションの形式 | [session-restore.md](../dev/session-restore.md)、[buffer-model.md](../dev/buffer-model.md) §9                 |
| §8 ファイルの監視                           | [buffer-model.md](../dev/buffer-model.md) §8                                                                  |
| §9 バッファの名前と表示                     | [buffer-model.md](../dev/buffer-model.md) §3                                                                  |
| §10 複数フレーム                            | [buffer-model.md](../dev/buffer-model.md) §7                                                                  |
| §11 変わるもの、§12 段階案                  | [migration-plan.md](migration-plan.md)(M7b)                                                                   |
| §13 決めていないこと                        | [buffer-model.md](../dev/buffer-model.md) §10                                                                 |
| §14 プロジェクト・ルート                    | [buffer-model.md](../dev/buffer-model.md) §6.2〜6.8(§14.3 → §6.4、§14.7 → §6.8)                               |

### `interaction-model.md`

| 当時の節                                      | 現在                                                                                                             |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| §2 用語とモデル、§3 buffer のライフサイクル   | [interaction-model.md](../dev/interaction-model.md) §1、[buffer-model.md](../dev/buffer-model.md) §2・§8         |
| §4 閲覧位置                                   | [interaction-model.md](../dev/interaction-model.md) §3                                                           |
| §5 参照履歴(§5.1〜§5.5)                       | [interaction-model.md](../dev/interaction-model.md) §4(§4.1〜§4.4、§5.5 は §4.1 と §7)                           |
| §5b 仮想 buffer と行アンカー                  | [interaction-model.md](../dev/interaction-model.md) §5                                                           |
| §6 入力とコマンド(§6.1 IME、§6.2 count-words) | [interaction-model.md](../dev/interaction-model.md) §6(§6.1、§6.2)                                               |
| §6b UI の言語と、macOS / Emacs の使い分け     | [ui-conventions.md](../dev/ui-conventions.md)                                                                    |
| §7 PoC の検証シナリオ、§8 範囲外              | [poc-interaction-results.md](poc-interaction-results.md)、[interaction-model.md](../dev/interaction-model.md) §7 |

### `integration-protocol.md`

契約、逆方向の連携、経緯に分けた。

| 当時の節                                  | 現在                                                                                                                                                                                             |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| §1 目的と範囲、§2 利用シーン、§3 基本方針 | [integration-protocol.md](../dev/integration-protocol.md) §1、§2                                                                                                                                 |
| §4 契約(URL・CLI・Emacs)                  | 同 §4.1、§5、§6、§7                                                                                                                                                                              |
| §5 アプリ側の挙動、§6 セキュリティ        | 同 §4、§3.6、§8(プロジェクトの決め方と信頼するルートは廃止。[file-access.md](../dev/file-access.md) に置き換わった)                                                                              |
| §7 互換性                                 | 同 §3.5                                                                                                                                                                                          |
| §8 実機確認、§9 合意事項                  | [poc-integration-results.md](poc-integration-results.md) §3、§2                                                                                                                                  |
| §10 逆方向の連携                          | [edit-location.md](../dev/edit-location.md)(要件 §2、位置の特定 §4、ペイロード §5、エディタ側の照合 §6、未決 §8)、方式の比較と合意は [poc-integration-results.md](poc-integration-results.md) §5 |
| §11 IPC(ソケット)                         | [integration-protocol.md](../dev/integration-protocol.md) §3、§6、§7(実機確認は [poc-integration-results.md](poc-integration-results.md) §4)                                                     |
| §12 配布方式                              | [distribution.md](../dev/distribution.md) §1、[poc-integration-results.md](poc-integration-results.md) §2.1                                                                                      |
| §13〜§15 実装の記録(M4〜M6)               | [integration-protocol.md](../dev/integration-protocol.md)、[edit-location.md](../dev/edit-location.md)、[poc-integration-results.md](poc-integration-results.md) §6                              |
| §16 プロジェクトを持たない設計への変更    | [integration-protocol.md](../dev/integration-protocol.md) §4.1、§6、[file-access.md](../dev/file-access.md)                                                                                      |

### `release.md`

| 当時の内容                                                 | 現在                                                   |
| ---------------------------------------------------------- | ------------------------------------------------------ |
| 対応するアーキテクチャ、アイコン、同梱するもの、署名の設計 | [distribution.md](../dev/distribution.md)              |
| 最初のリリースの失敗、同梱物の検査、アイコンの決定         | [distribution-decisions.md](distribution-decisions.md) |
| リリースの手順、まっさらな Mac での確認                    | [release.md](../dev/release.md)                        |
