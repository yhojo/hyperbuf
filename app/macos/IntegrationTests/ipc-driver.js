// 統合テスト(IPC)用のドライバ(WebView の中で実行される)。
// ミニバッファの「範囲外のファイルを開きますか」に、パスの名前で自動的に答える:
//   /approve/ を含むパス → yes、/deny/ を含むパス → no、/wait/ を含むパス → 答えずに、少しして Esc で取り消す。
let answered = null;
setInterval(() => {
  const mini = document.getElementById("minibuffer");
  if (!mini || mini.hidden) {
    answered = null;
    return;
  }
  const label = document.getElementById("prompt-label").textContent ?? "";
  if (answered === label) return;
  answered = label;
  const input = document.getElementById("prompt-input");
  const press = (key, code) =>
    input.dispatchEvent(new KeyboardEvent("keydown", { key, code, bubbles: true, cancelable: true }));
  const type = (text) => {
    input.value = text;
    input.dispatchEvent(new Event("input"));
  };
  if (label.includes("/approve/")) {
    type("yes");
    press("Enter", "Enter");
  } else if (label.includes("/deny/")) {
    type("no");
    press("Enter", "Enter");
  } else if (label.includes("/wait/")) {
    setTimeout(() => press("Escape", "Escape"), 1500);
  }
}, 50);
// このスクリプトが終わると、ハーネスがアプリを終了させる。テストの終了までは終わらせない(通常は、
// その前に、シェルスクリプトがアプリを終了させる)。解決しない Promise は、WebKit が「到達できない」と扱うので、
// 十分長い待ち時間のあとで解決する。
return new Promise((resolve) => setTimeout(() => resolve("driver timeout"), 10 * 60 * 1000));
