#!/usr/bin/env python3
"""Project navigation PoC 用の、大きな Markdown プロジェクトを生成する(乱数は固定シード)。

使い方: gen-corpus.py <出力先ディレクトリ> <ファイル数>

- 階層は深さ 3、1 ディレクトリあたり約 20 ファイル。
- 各文書は見出し・段落・リスト・コード・表・他の文書へのリンクを含み、1 ファイル数 KB。
- 検索の検証用に、頻度の異なる語を仕込む:
    "buffer"       … ほぼ全ファイルに出現(高頻度)
    "reference"    … 約 20% のファイルに出現(中頻度)
    "zyxwv-rare-N" … 5 ファイルだけに出現(低頻度。N = 0..4)
    "ハイパーバッファ" … 約 2% のファイルに出現(日本語)
"""
import os, random, sys

out, n = sys.argv[1], int(sys.argv[2])
rng = random.Random(20261008)
en = "alpha beta gamma delta window frame buffer history anchor heading render parser cache index search file path link scroll cursor keymap command minibuffer split tree node leaf event handler queue stream token module package loader watcher session project document section table list code block image diagram formula".split()
ja = "文書 設計 参照 履歴 検索 一覧 表示 更新 位置 見出し 分割 画面 入力 操作 確認 変換 構造 仕様 実装 検証 性能 応答 図 数式 画像 連携".split()

def sentence():
    words = [rng.choice(en) for _ in range(rng.randint(4, 9))] + [rng.choice(ja) for _ in range(rng.randint(2, 5))]
    rng.shuffle(words)
    return " ".join(words).capitalize() + "。"

def para():
    return " ".join(sentence() for _ in range(rng.randint(2, 6)))

dirs = []
per = 20
count_dirs = max(1, n // per)
for i in range(count_dirs):
    dirs.append(os.path.join(f"area{i % 7}", f"topic{i // 7 % 11}", f"group{i}"))
files = [os.path.join(dirs[i % count_dirs], f"doc-{i:05d}.md") for i in range(n)]
rare_at = set(rng.sample(range(n), 5))
rare = {idx: k for k, idx in enumerate(sorted(rare_at))}

for i, rel in enumerate(files):
    lines = [f"# 文書 {i}: {rng.choice(en)} {rng.choice(ja)}", ""]
    for s in range(rng.randint(3, 8)):
        lines += [f"## セクション {s} {rng.choice(en)}", "", para(), ""]
        if rng.random() < 0.4:
            lines += ["- " + sentence() for _ in range(rng.randint(2, 5))] + [""]
        if rng.random() < 0.3:
            lines += ["```python", f"def f{s}(x):", f"    return x * {rng.randint(1, 99)}  # {rng.choice(en)}", "```", ""]
        if rng.random() < 0.2:
            lines += ["| a | b |", "| --- | --- |", f"| {rng.choice(en)} | {rng.randint(1, 999)} |", ""]
        if rng.random() < 0.5:
            target = rng.choice(files)
            lines += [f"関連: [{os.path.basename(target)}]({os.path.relpath(target, os.path.dirname(rel))})", ""]
    if rng.random() < 0.2:
        lines += ["この文書は reference を説明します。", ""]
    if rng.random() < 0.02:
        lines += ["ハイパーバッファでの検索対象です。", ""]
    if i in rare:
        lines += [f"唯一の印: zyxwv-rare-{rare[i]}", ""]
    path = os.path.join(out, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

total = sum(os.path.getsize(os.path.join(out, r)) for r in files)
print(f"{n} files, {len(set(os.path.dirname(f) for f in files))} dirs, {total/1024/1024:.1f} MB -> {out}")
