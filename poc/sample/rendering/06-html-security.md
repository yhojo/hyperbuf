# HTML とセキュリティ

表示後、アラートが出たり、画面が崩れたり、外部へ通信したりしないことを確認します。

## script

<script>alert("script")</script>

## イベントハンドラ

<img src="img/dot.png" onerror="alert('onerror')" onload="alert('onload')">

<div onclick="alert('click')" onmouseover="alert('hover')">イベントハンドラ付き div</div>

## javascript: URL

<a href="javascript:alert('js')">javascript リンク</a>

[markdown のリンク](javascript:alert('md'))

## iframe / object / embed / form

<iframe src="https://example.com"></iframe>

<object data="https://example.com"></object>

<form action="https://example.com"><input name="x"><button>送信</button></form>

## style と位置の乗っ取り

<div style="position:fixed;top:0;left:0;width:100vw;height:100vh;background:red">全画面を覆う</div>

<style>body { display: none }</style>

## SVG の埋め込み

<svg onload="alert('svg')"><script>alert(1)</script><circle r="10"/></svg>

## id の衝突(アプリの DOM を壊さない)

<span id="echo" name="status">id=echo</span>

## 文書内の `meta refresh` など

<meta http-equiv="refresh" content="0;url=https://example.com">

<base href="https://example.com/">

最後まで表示されれば OK です。
