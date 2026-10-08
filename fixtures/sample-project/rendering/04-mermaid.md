# Mermaid

## フローチャート

```mermaid
flowchart LR
  A[キー入力] --> B{プレフィックス?}
  B -- はい --> C[待機]
  B -- いいえ --> D[コマンド実行]
  C --> D
  D --> E[再描画]
```

## シーケンス図

```mermaid
sequenceDiagram
  participant W as WebView
  participant H as Host
  W->>H: listFiles()
  H-->>W: ["index.md", ...]
  W->>H: readFile(path)
  H-->>W: text
```

## クラス図

```mermaid
classDiagram
  class Window { +history +index }
  class Buffer { +path +text }
  Window --> Buffer : 表示
```

## 状態遷移図

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Prefix: C-x
  Prefix --> Idle: コマンド
```

## ガント

```mermaid
gantt
  title PoC
  dateFormat YYYY-MM-DD
  Interaction :done, 2026-10-08, 1d
  Rendering   :active, 2026-10-08, 2d
```

## エラー(構文エラー): この下の文章は表示されます

```mermaid
flowchart LR
  A --> 
  this is not valid mermaid ((
```

## 日本語ラベルと長い図

```mermaid
graph TD
  開始 --> 読み込み --> 解析 --> 描画 --> 表示
```

図の後ろの文章です。
