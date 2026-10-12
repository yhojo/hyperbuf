#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Yasuo Hojo
# 統合テスト(UI): 実際の HyperBuf.app(デバッグビルド、WKWebView)で、M3 の操作を検査する。
#   文書内のインクリメンタル検索(C-s / C-r)、outline 風の見出し移動、スクロールの補完、
#   キーマップの設定(config.json の keybindings)と describe-bindings(C-h b)。
# キー入力は、ページ内で KeyboardEvent を発行する(ネイティブのキー経路の確認は、手動)。
# GUI セッションが要る。利用者の実際のソケット・設定・信頼するルートは使わない。
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"

app/macos/scripts/make-app.sh debug >/dev/null
app="$root/app/macos/.build/HyperBuf.app"
project="$(cd "$root/fixtures/sample-project" && pwd -P)"

tmp="$(mktemp -d)"
cleanup() {
  pkill -f "$app/Contents/MacOS/HyperBuf" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/cmd" "$tmp/sock"
# 利用者の設定: M-p に back を割り当て、C-f を外し、不正な設定を 3 つ入れる(無視されて、一覧に出るはず)
cat > "$tmp/config.json" <<'JSON'
{
  "keybindings": {
    "M-p": "back",
    "C-f": null,
    "C-x 9": "no-such-command",
    "Ctrl-y": "back",
    "C-g": "forward"
  },
  "trustedUrls": ["https://trusted.example/*"]
}
JSON

export TMP_DIR="$tmp" PROJECT_DIR="$project"
open -a "$app" \
  --env "HYPERBUF_SOCKET_PATH=$tmp/sock/hb.sock" \
  --env "HYPERBUF_TRUSTED_ROOTS=$tmp/trusted.json" \
  --env "HYPERBUF_SESSION_DIR=$tmp/sessions" \
  --env "HYPERBUF_TEST_OPEN_LOG=$tmp/open.log" \
  --env "HYPERBUF_TRUSTED_SITES=$tmp/sites.json" \
  --env "HYPERBUF_CONFIG=$tmp/config.json" \
  --env "HYPERBUF_TEST_COMMANDS=$tmp/cmd" \
  --args "$project"

python3 - <<'PY'
import json, os, sys, time

tmp = os.environ["TMP_DIR"]
cmd_dir = os.path.join(tmp, "cmd")
failures = []
seq = [0]

def check(name, condition, detail=""):
    print(("  ✔ " if condition else "  ✘ ") + name + ("" if condition else f"  {detail}"))
    if not condition:
        failures.append(name)

def page(js, timeout=30):
    seq[0] += 1
    name = f"{seq[0]:03d}"
    open(f"{cmd_dir}/{name}.js.tmp", "w", encoding="utf-8").write(js)
    os.rename(f"{cmd_dir}/{name}.js.tmp", f"{cmd_dir}/{name}.js")
    deadline = time.time() + timeout
    while not os.path.exists(f"{cmd_dir}/{name}.result"):
        if time.time() > deadline:
            raise RuntimeError("ページの応答がありません: " + js[:80])
        time.sleep(0.05)
    text = open(f"{cmd_dir}/{name}.result", encoding="utf-8").read()
    if text.startswith("ERROR"):
        raise RuntimeError(text)
    return text.removeprefix("RESULT: ")

# ページで使う補助(キー入力・状態)。各 page() の先頭に付ける
HELPERS = """
const P = %s;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hb = window.__hyperbuf;
const press = async (...keys) => {
  for (const [k, code, mods] of keys) window.dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...(mods ?? {}) }));
  await hb.keyboard.idle(); await sleep(80);
};
// C-s は、確定・取消まで終わらないコマンドなので、完了を待たずに発行する
const fire = async (k, code, mods = {}) => { window.dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...mods })); await sleep(80); };
const input = () => document.getElementById('prompt-input');
const typeIn = (t) => { input().value = t; input().dispatchEvent(new Event('input')); };
const pressIn = (k, code, mods = {}) => input().dispatchEvent(new KeyboardEvent('keydown', { key: k, code, bubbles: true, cancelable: true, ...mods }));
const content = () => document.querySelector('.win.selected .content');
const heading = () => { let b = null; for (const h of content().querySelectorAll('h1,h2,h3,h4,h5,h6')) if (h.offsetTop <= content().scrollTop + 9) b = h.textContent; return b; };
const mini = () => ({ label: document.getElementById('prompt-label').textContent, count: document.getElementById('prompt-count').textContent, hidden: document.getElementById('minibuffer').hidden });
const C = (k, code) => [['c', 'KeyC', { ctrlKey: true }], [k, code, { ctrlKey: true }]];
"""
def run(body):
    return json.loads(page(HELPERS % json.dumps(os.environ["PROJECT_DIR"]) + body))

# 起動(Web コアの準備)を待つ
t0 = time.time()
while time.time() - t0 < 60:
    try:
        if page("return String(!!window.__hyperbuf)", timeout=5) == "true":
            break
    except RuntimeError:
        pass
    time.sleep(0.3)
else:
    sys.exit("アプリが起動しませんでした")

print("WKWebView の機能")
r = run("return JSON.stringify({ highlights: !!(window.CSS && CSS.highlights && window.Highlight) })")
check("CSS Custom Highlight API が使える(なければ、現在の一致だけが選択状態になる)", r["highlights"], r)

print("文書内のインクリメンタル検索(C-s / C-r)")
r = run("""
await hb.open(P + '/long.md'); await sleep(300);
await fire('s','KeyS',{ctrlKey:true});
const opened = mini();
typeIn('セクション 3'); await sleep(100);
const typed = { ...mini(), sel: String(getSelection()), hl: CSS.highlights.get('hb-search')?.size, cur: CSS.highlights.get('hb-search-current')?.size, focus: document.activeElement?.id };
pressIn('s','KeyS',{ctrlKey:true}); await sleep(80); const next = mini();
pressIn('r','KeyR',{ctrlKey:true}); await sleep(80); const prev = mini();
typeIn('存在しない語zzz'); await sleep(80); const failing = mini();
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
const cancelled = { hidden: mini().hidden, top: content().scrollTop, sel: String(getSelection()), hl: CSS.highlights.has('hb-search') };
await fire('s','KeyS',{ctrlKey:true}); typeIn('セクション 20'); await sleep(80);
pressIn('Enter','Enter'); await sleep(80);
const accepted = { hidden: mini().hidden, sel: String(getSelection()), top: Math.round(content().scrollTop), hl: CSS.highlights.has('hb-search') };
return JSON.stringify({ opened, typed, next, prev, failing, cancelled, accepted });
""")
check("C-s で検索が始まる", r["opened"]["label"] == "I-search: " and not r["opened"]["hidden"], r["opened"])
check("入力のたびに、一致を数えて、選択・ハイライトする", r["typed"]["count"].startswith("[1/") and r["typed"]["cur"] == 1 and r["typed"]["hl"] >= 2, r["typed"])
check("入力中は、文書に選択を作らず、フォーカスが入力欄に残る(奪われると、続きの入力が届かない)", r["typed"]["sel"] == "" and r["typed"]["focus"] == "prompt-input", r["typed"])
check("C-s で次、C-r で前の一致", r["next"]["count"].startswith("[2/") and r["prev"]["count"].startswith("[1/") and "backward" in r["prev"]["label"], (r["next"], r["prev"]))
check("一致がなければ Failing", r["failing"]["count"] == "Failing" and r["failing"]["label"].startswith("Failing"), r["failing"])
check("C-g で、始めた位置に戻り、選択・ハイライトが消える", r["cancelled"]["hidden"] and r["cancelled"]["top"] == 0 and r["cancelled"]["sel"] == "" and not r["cancelled"]["hl"], r["cancelled"])
check("RET で、その位置にとどまり、一致が選択状態で残る(ハイライトは消える)", r["accepted"]["hidden"] and r["accepted"]["sel"] == "セクション 20" and r["accepted"]["top"] > 1000 and not r["accepted"]["hl"], r["accepted"])
r = run("""
content().scrollTop = 0; await sleep(50);
await fire('s','KeyS',{ctrlKey:true}); pressIn('s','KeyS',{ctrlKey:true}); await sleep(100);
const reuse = { text: input().value, count: mini().count };
pressIn('g','KeyG',{ctrlKey:true}); await sleep(50);
await hb.open(P + '/index.md'); await sleep(300);
await fire('s','KeyS',{ctrlKey:true}); typeIn('buffer'); await sleep(80); const lower = mini().count;
typeIn('Buffer'); await sleep(80); const upper = mini().count;
pressIn('g','KeyG',{ctrlKey:true});
return JSON.stringify({ reuse, lower, upper });
""")
check("空のときの C-s は、前回の検索語を使う", r["reuse"]["text"] == "セクション 20" and r["reuse"]["count"].startswith("["), r["reuse"])
r3 = run("""
await hb.open(P + '/long.md'); await sleep(300);
await fire('s','KeyS',{ctrlKey:true}); typeIn('セクション'); await sleep(80);
pressIn('Process','Enter',{keyCode:229}); await sleep(80);
const duringIme = { hidden: mini().hidden };
pressIn('Enter','Enter'); await sleep(80);
return JSON.stringify({ duringIme, after: mini().hidden });
""")
check("日本語入力の確定の Enter(keyCode 229)では、検索を終えない。次の Enter で終える", r3["duringIme"]["hidden"] is False and r3["after"] is True, r3)
r4 = run("""
await hb.open(P + '/long.md'); await sleep(300); content().scrollTop = 0; await sleep(50);
await fire('s','KeyS',{ctrlKey:true}); typeIn('セクション'); await sleep(80);
pressIn('s','KeyS',{ctrlKey:true}); await sleep(50); pressIn('s','KeyS',{ctrlKey:true}); await sleep(80);
typeIn(''); typeIn('セクション'); await sleep(80);
const count = mini().count;
pressIn('g','KeyG',{ctrlKey:true});
return JSON.stringify({ count });
""")
check("検索語がいったん空になって元に戻っても(日本語入力の確定)、選んでいた一致から動かない", r4["count"].startswith("[3/"), r4)
r5 = run("""
await hb.open(P + '/long.md'); await sleep(300); content().scrollTop = 0; await sleep(50);
const comp = (t) => { input().value = t; input().dispatchEvent(new InputEvent('input', { isComposing: true })); };
await fire('s','KeyS',{ctrlKey:true});
comp('ｓ'); await sleep(50); comp('セ'); await sleep(50); comp('セクション 7'); await sleep(50);
const during = mini().count;
typeIn(''); typeIn('セクション 7'); await sleep(80);
const after = mini().count;
const selTop = Math.round(content().scrollTop);
pressIn('g','KeyG',{ctrlKey:true});
return JSON.stringify({ during, after });
""")
check("日本語入力の変換中の一致に基準が引きずられず、確定した語を、変換を始めた位置から探す", r5["during"].startswith("[1/") and r5["after"].startswith("[1/"), r5)
r6 = run("""
await hb.open(P + '/long.md'); await sleep(300);
await fire('x','KeyX',{ctrlKey:true}); await fire('b','KeyB');
const before = input().value;
typeIn('ab'); pressIn('Dead','KeyN',{altKey:true}); input().value = 'ab˜';
input().dispatchEvent(new CompositionEvent('compositionstart')); await sleep(100);
const restored = input().value;
pressIn('g','KeyG',{ctrlKey:true}); await sleep(50);
return JSON.stringify({ restored });
""")
check("Option つきの Dead キー(M-n の ˜ など)で始まった変換は、取り消して、入力欄が元に戻る", r6["restored"] == "ab", r6)
r2 = run("""
await hb.open(P + '/long.md'); await sleep(300); content().scrollTop = 0; await sleep(50);
await fire('s','KeyS',{ctrlKey:true}); typeIn('セクション'); await sleep(80);
pressIn('s','KeyS',{ctrlKey:true}); await sleep(50); pressIn('s','KeyS',{ctrlKey:true}); await sleep(80);
const before = mini().count;
pressIn('Enter','Enter'); await sleep(100);
const sel = String(getSelection());
const rg = getSelection().rangeCount ? getSelection().getRangeAt(0) : null;
const where = rg ? Math.round(rg.getBoundingClientRect().top) : null;
const first = (() => { const w = document.createTreeWalker(content(), NodeFilter.SHOW_TEXT); for (let n = w.nextNode(); n; n = w.nextNode()) { const i = n.data.indexOf('セクション'); if (i >= 0) { const q = document.createRange(); q.setStart(n, i); q.setEnd(n, i + 5); return Math.round(q.getBoundingClientRect().top); } } return null; })();
await fire('s','KeyS',{ctrlKey:true}); typeIn('参照'); await sleep(80);
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
await fire('s','KeyS',{ctrlKey:true}); pressIn('s','KeyS',{ctrlKey:true}); await sleep(100);
const reused = { text: input().value, count: mini().count };
pressIn('g','KeyG',{ctrlKey:true});
return JSON.stringify({ before, sel, where, first, reused });
""")
check("C-s を重ねて RET: 強調していた一致が、選択状態で残る(先頭の一致へ戻らない)", r2["before"].startswith("[3/") and r2["sel"] == "セクション" and r2["where"] != r2["first"], r2)
check("C-g で抜けても、次の C-s C-s で、その検索語を使う", r2["reused"]["text"] == "参照", r2["reused"])
check("大文字を含む検索語だけ、大文字小文字を区別する", r["lower"].startswith("[1/") and r["upper"] == "Failing", r)

print("outline 風の見出し移動・スクロール")
r = run("""
await hb.open(P + '/long.md'); await sleep(300);
const hist = document.querySelector('.mode-line .ml-hist').textContent;
const seq = [];
await press(...C('n','KeyN')); seq.push(heading());
await press(...C('n','KeyN')); seq.push(heading());
await press(...C('n','KeyN')); seq.push(heading());
await press(...C('p','KeyP')); seq.push(heading());
await press(...C('f','KeyF')); seq.push(heading());
await press(...C('b','KeyB')); seq.push(heading());
await press(...C('u','KeyU')); seq.push(heading());
await press(...C('u','KeyU')); const none = document.getElementById('echo').textContent;
const sameHistory = document.querySelector('.mode-line .ml-hist').textContent === hist;
await press(['>','Period',{altKey:true,shiftKey:true}]);
const end = Math.abs(content().scrollTop + content().clientHeight - content().scrollHeight) < 4;
await press(['<','Comma',{altKey:true,shiftKey:true}]);
const top = content().scrollTop;
await press([' ','Space']); const down = Math.round(content().scrollTop);
await press(['Backspace','Backspace']); const up = Math.round(content().scrollTop);
return JSON.stringify({ seq, none, sameHistory, end, top, down, up, page: content().clientHeight });
""")
check("C-c C-n / C-p / C-f / C-b / C-u", r["seq"] == ["セクション 1", "セクション 2", "セクション 3", "セクション 2", "セクション 3", "セクション 2", "長い文書"], r["seq"])
check("先頭のレベルより上はない", "ありません" in r["none"], r["none"])
check("見出し移動は、参照履歴に積まれない", r["sameHistory"])
check("M-> / M-<(Option+Shift+. / ,)", r["end"] and r["top"] == 0, r)
check("SPC で 1 画面下、DEL で戻る", r["down"] > r["page"] * 0.8 and r["up"] == 0, r)

print("リンクの選択(TAB / S-TAB): 見えている範囲から始める")
links_path = os.path.join(tmp, "links.md")
open(links_path, "w", encoding="utf-8").write(
    "# リンクの選択\n\n先頭の [top](top.md) です。\n\n"
    + "".join(f"段落 {i}\n\n" for i in range(60))
    + "中ほどの [middle](middle.md) です。\n\n"
    + "".join(f"段落 {i}\n\n" for i in range(60, 120))
    + "末尾の [bottom](bottom.md) です。\n\n"
)
r = run("""
const f = %s;
await hb.open(f); await sleep(400);
const c = content();
const focus = () => document.querySelector('.win.selected .content a.link-focus')?.getAttribute('href') ?? null;
const link = (h) => c.querySelector('a[href="' + h + '"]');
// 中ほどのリンクが見える位置までスクロールして、TAB: 先頭ではなく、見えている最初のリンク
link('middle.md').scrollIntoView({ block: 'center' }); await sleep(200);
await press(['Tab','Tab']); const first = focus();
await press(['Tab','Tab']); const second = focus();   // 次は、末尾
// フォーカスしたリンクが、見えなくなったら、見えている範囲から選び直す
c.scrollTop = 0; await sleep(200);
await press(['Tab','Tab']); const afterScrollUp = focus();
// S-TAB は、見えている最後のリンクから
link('middle.md').scrollIntoView({ block: 'center' }); await sleep(200);
await press(['Tab','Tab',{ shiftKey: true }]); const back = focus();
return JSON.stringify({ first, second, afterScrollUp, back });
""" % json.dumps(links_path))
check("TAB: 中ほどを見ているときは、先頭ではなく、見えている最初のリンクを選ぶ", r["first"] == "middle.md", r)
check("TAB を続けると、次のリンクへ進む", r["second"] == "bottom.md", r)
check("選んだリンクが画面の外に出たら、見えている範囲から選び直す(文書の先頭のリンク)", r["afterScrollUp"] == "top.md", r)
check("S-TAB: 見えている範囲の最後のリンクから", r["back"] == "middle.md", r)

print("外部リンク(ブラウザで開く): 確認 → trustedUrls → always")
ext_path = os.path.join(tmp, "ext.md")
open(ext_path, "w", encoding="utf-8").write(
    "# 外部リンク\n\n"
    "[信頼する](https://trusted.example/page)\n\n"
    "[その他](https://other.example/x)\n\n"
    "[認証情報つき](https://user:pw@evil.example/)\n\n"
    "[メール](mailto:someone@example.com)\n"
)
r = run("""
const f = %s;
await hb.open(f); await sleep(400);
const c = content();
const click = async (h) => { c.querySelector('a[href="' + h + '"]').click(); await sleep(350); };
const prompt = () => ({ hidden: mini().hidden, label: mini().label });
const answer = async (text) => { typeIn(text); pressIn('Enter','Enter'); await sleep(350); };
const out = {};
await click('https://trusted.example/page'); out.trusted = prompt();
await click('https://other.example/x'); out.confirm = prompt(); await answer('no');
await click('https://other.example/x'); out.again = prompt(); await answer('yes');
await click('https://other.example/x'); out.third = prompt(); await answer('always');
await click('https://other.example/x'); out.remembered = prompt();
await click('https://user:pw@evil.example/'); out.denied = { ...prompt(), echo: document.getElementById('echo').textContent };
await click('mailto:someone@example.com'); out.mailto = prompt(); await answer('no');
return JSON.stringify(out);
""" % json.dumps(ext_path))
opened = open(os.path.join(tmp, "open.log"), encoding="utf-8").read().split() if os.path.exists(os.path.join(tmp, "open.log")) else []
check("trustedUrls に合う URL は、確認なしで、ブラウザで開く", r["trusted"]["hidden"] and "https://trusted.example/page" in opened, (r["trusted"], opened))
check("それ以外は、URL 全体を見せて、確認する", (not r["confirm"]["hidden"]) and "https://other.example/x" in r["confirm"]["label"] and "always" in r["confirm"]["label"], r["confirm"])
check("no と答えると、開かない。yes なら、開く(毎回、確認する)", opened.count("https://other.example/x") == 3 and not r["again"]["hidden"] and not r["third"]["hidden"], (r["again"], opened))
check("always で、そのサイトを記憶し、次からは確認しない", r["remembered"]["hidden"] and json.load(open(os.path.join(tmp, "sites.json")))["origins"] == ["https://other.example"], (r["remembered"], opened))
check("ユーザー名・パスワードを含む URL は、確認もせず、開かない", r["denied"]["hidden"] and "evil.example" not in " ".join(opened) and "開きません" in r["denied"]["echo"], (r["denied"], opened))
check("mailto は、毎回、確認する(always は出ない)", (not r["mailto"]["hidden"]) and "always" not in r["mailto"]["label"] and "mailto:someone@example.com" not in opened, r["mailto"])

print("キーマップの設定と describe-bindings")
r = run("""
await hb.open(P + '/long.md'); await sleep(300);
await hb.open(P + '/index.md'); await sleep(200);
const before = document.querySelector('.mode-line').textContent;
await press(['p','KeyP',{altKey:true}]);               // M-p(利用者が back に割り当てた)
const afterMp = document.querySelector('.mode-line').textContent;
await press(['f','KeyF',{ctrlKey:true}]);              // C-f(利用者が外した → 何も起きない)
const afterCf = document.querySelector('.mode-line').textContent;
await press(['b','KeyB',{ctrlKey:true}]);              // C-b(標準のまま back)
const afterCb = document.querySelector('.mode-line').textContent;
await press(['h','KeyH',{ctrlKey:true}], ['b','KeyB']); // C-h b
const header = document.querySelector('.mode-line').textContent;
const text = content().textContent;
const rows = [...content().querySelectorAll('tr')].map((tr) => tr.textContent);
return JSON.stringify({ before, afterMp, afterCf, afterCb, header, text, rows });
""")
check("利用者が割り当てた M-p が、back として働く", "long.md" in r["afterMp"], r)
check("利用者が外した C-f は、何も起こさない", r["afterCf"] == r["afterMp"], r)
check("標準のままの C-b は、働く", r["afterCb"] != r["afterCf"] or "履歴" in r["afterCb"], r["afterCb"])
check("C-h b で、キー割り当ての一覧(仮想 buffer)が開く", "*Help: keybindings*" in r["header"], r["header"])
check("一覧に、利用者の割り当て(M-p)と、標準の割り当てが出る", "M-p" in r["text"] and "describe-bindings" in r["text"] and "C-x 2" in r["text"], r["text"][:300])
forward_row = next((row for row in r["rows"] if "`forward`" in row or row.split("forward")[0:1] and "forward" in row), "")
check("外した C-f は、forward の割り当てに出ない(s-] だけ)", "s-]" in forward_row and "C-f" not in forward_row, forward_row)
check("利用者が足した M-p は、back の割り当てに出る", any("M-p" in row and "back" in row for row in r["rows"]), [row for row in r["rows"] if "back" in row])
check("不正な設定(不明なコマンド・不正な表記・C-g)は、無視して、一覧に出る",
      all(s in r["text"] for s in ["設定の問題", "no-such-command", "Ctrl-y", "C-g"]), r["text"][:600])

print("ファイルを開く(C-x C-f のパス補完・C-x p f)・ミニバッファ(候補・履歴)・kill-buffer")
r = run("""
await hb.open(P + '/index.md'); await sleep(200);
await hb.open(P + '/architecture.md'); await sleep(200);
await hb.open(P + '/long.md'); await sleep(200);
const cands = () => [...document.querySelectorAll('#candidates li')];
await fire('x','KeyX',{ctrlKey:true}); await fire('f','KeyF',{ctrlKey:true});       // C-x C-f
await sleep(200);
const initial = input().value;
const empty = { texts: cands().slice(0, 6).map((li) => li.textContent), count: document.getElementById('prompt-count').textContent };
typeIn(initial + 'arch'); await sleep(200);
const typed = { first: cands()[0]?.textContent, marked: [...(cands()[0]?.querySelectorAll('b') ?? [])].map((b) => b.textContent), on: cands()[0]?.className };
pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(250);
const opened = document.querySelector('.mode-line').textContent;
// ディレクトリは、RET で確定せず、その中に入る
await fire('x','KeyX',{ctrlKey:true}); await fire('f','KeyF',{ctrlKey:true}); await sleep(200);
const initial2 = input().value;
typeIn(initial2 + 'rend'); await sleep(200);
const dirFirst = cands()[0]?.textContent;
pressIn('Enter','Enter'); await sleep(250);
const descended = { value: input().value, texts: cands().slice(0, 4).map((li) => li.textContent), hidden: document.getElementById('minibuffer').hidden };
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
// 入力の履歴(M-p)
await fire('x','KeyX',{ctrlKey:true}); await fire('f','KeyF',{ctrlKey:true}); await sleep(200);
pressIn('p','KeyP',{altKey:true}); await sleep(80);
const recalled = input().value;
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
return JSON.stringify({ initial, empty, typed, opened, dirFirst, descended, recalled });
""")
check("C-x C-f: 入力欄は、基準のディレクトリ(~/ 形式)から始まる", r["initial"].startswith("~/") and r["initial"].endswith("fixtures/sample-project/"), r["initial"])
check("候補は、そのディレクトリの中だけ(ディレクトリが先、.md が続く)", r["empty"]["texts"][0] == "rendering/" and "long.md" in r["empty"]["texts"] and "index.md" in r["empty"]["texts"], r["empty"])
check("候補の件数が出る(n/全体)", "/" in r["empty"]["count"], r["empty"])
check("入力した語に一致した部分が、強調される", r["typed"]["first"] == "architecture.md" and r["typed"]["marked"] == ["arch"] and r["typed"]["on"] == "on", r["typed"])
check("RET で、その文書が開く", "architecture.md" in r["opened"], r["opened"])
check("ディレクトリは RET で確定せず、中に入る(入力欄の末尾が / になり、候補が更新される)", r["dirFirst"] == "rendering/" and r["descended"]["value"].endswith("rendering/") and not r["descended"]["hidden"] and "rendering/" not in r["descended"]["texts"], r["descended"])
check("M-p で、前回確定した値を呼び出せる(Emacs の履歴と同じ)", r["recalled"].endswith("architecture.md"), r["recalled"])

r = run("""
await hb.open(P + '/long.md'); await sleep(200);
const cands = () => [...document.querySelectorAll('#candidates li')];
await fire('x','KeyX',{ctrlKey:true}); await fire('p','KeyP'); await fire('f','KeyF'); await sleep(400);   // C-x p f
const label = document.getElementById('prompt-label').textContent;
const listed = cands().map((li) => li.textContent);
typeIn('rend'); await sleep(250);
const filtered = cands().map((li) => li.textContent);
pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(300);
const header = document.querySelector('.mode-line').textContent;
// 基準を ../ に切り替えて、基準の外のファイルに届く
await fire('x','KeyX',{ctrlKey:true}); await fire('p','KeyP'); await fire('f','KeyF'); await sleep(300);
typeIn('../../sample'); await sleep(500);
const outer = cands().map((li) => li.textContent);
pressIn('g','KeyG',{ctrlKey:true}); await sleep(80);
return JSON.stringify({ label, listed, filtered, header, outer });
""")
check("C-x p f: 基準のディレクトリ以下を再帰で一覧にする(相対パス)", "Find file (tree)" in r["label"] and "long.md" in r["listed"] and any(x.startswith("rendering/") for x in r["listed"]), r["listed"])
check("絞り込んで RET で開く", r["filtered"] and r["filtered"][0].startswith("rendering/") and "long.md" not in r["header"] and ".md" in r["header"], (r["filtered"], r["header"]))
check("../ を入力すると、基準が切り替わり、基準の外のファイルも一覧になる", any(x.startswith("sample-project/") for x in r["outer"]), r["outer"][:8])

print("バッファ名の uniquify と、仮想バッファ(検索結果)の起点")
r = run("""
const ROOT = P.slice(0, P.lastIndexOf('/fixtures/'));
await hb.open(ROOT + '/README.md'); await sleep(200);
await hb.open(ROOT + '/emacs/README.md'); await sleep(200);
const headerBoth = document.querySelector('.mode-line').textContent;
await hb.search('Mermaid'); await sleep(500);
const searchHeader = document.querySelector('.mode-line').textContent;
return JSON.stringify({ headerBoth, searchHeader });
""")
check("同じ名前が複数あるときだけ、親ディレクトリを足す(README.md<emacs>)", "README.md<emacs>" in r["headerBoth"], r["headerBoth"])
check("検索結果の仮想バッファに、起点を添える(*search: …*<emacs>)", "*search: Mermaid*<emacs>" in r["searchHeader"], r["searchHeader"])

r = run("""
await hb.open(P + '/interaction.md'); await sleep(200);
const model = hb.ctx.model;
const hasBefore = model.buffers.has(P + '/interaction.md');
await fire('x','KeyX',{ctrlKey:true}); await fire('k','KeyK');                          // C-x k
const label = document.getElementById('prompt-label').textContent;
pressIn('Enter','Enter'); await hb.keyboard.idle(); await sleep(200);
const win = hb.ctx.model.root.win ?? null;
const histories = (function walk(n) { return n.type === 'leaf' ? [n.win.history.map((e) => e.path)] : n.children.flatMap(walk); })(model.root);
return JSON.stringify({ hasBefore, label, hasAfter: model.buffers.has(P + '/interaction.md'), mru: model.mru.slice(0, 3), histories, header: document.querySelector('.mode-line').textContent, echo: document.getElementById('echo').textContent });
""")
check("C-x k: 既定は、いまの buffer", "interaction.md" in r["label"], r["label"])
check("buffer が閉じて、履歴からも参照がなくなる", r["hasBefore"] and not r["hasAfter"] and all(not p.endswith("interaction.md") for h in r["histories"] for p in h), r)
check("閉じた buffer を表示していた window は、ひとつ前の参照を表示する", "interaction.md" not in r["header"], r["header"])
check("閉じたことが知らされる", "閉じました" in r["echo"], r["echo"])

if failures:
    print(f"\nNG: {len(failures)} 件")
    sys.exit(1)
print("\nOK")
PY
