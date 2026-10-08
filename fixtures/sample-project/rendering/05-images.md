# 画像と SVG

## ローカルの PNG

![小さな PNG](img/dot.png)

## ローカルの SVG(`<img>` 経由)

![図](img/diagram.svg)

## script を含む SVG(動いてはいけない)

![悪意のある SVG](img/evil.svg)

上の画像を表示しても、アラートなどが出なければ無害化できています。

## 外部画像(ブロックされる)

![外部画像](https://example.com/image.png)

## HTML の img

<img src="img/diagram.svg" width="120" alt="サイズ指定">

## 存在しない画像

![ない](img/missing.png)
