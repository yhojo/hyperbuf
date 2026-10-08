// 統合テスト(IPC)用のドライバ(WebView の中で実行される)。
// ミニバッファの「範囲外のファイルを開きますか」に、パスの名前で自動的に答える:
//   /approve/ を含むパス → yes、/deny/ を含むパス → no、/wait/ を含むパス → 答えない(期限切れで閉じることの確認)。
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
    // 答えない。要求の期限が切れたら、アプリが、この確認を閉じるはず(閉じたことを、テスト用のログに記録する)
    window.hyperbufHost.log("SAW wait prompt");
    const watch = setInterval(() => {
      if (document.getElementById("minibuffer").hidden) {
        window.hyperbufHost.log("HIDDEN wait prompt");
        clearInterval(watch);
      }
    }, 50);
  }
}, 50);
// このスクリプトが終わると、ハーネスがアプリを終了させる。テストの終了までは終わらせない(通常は、
// その前に、シェルスクリプトがアプリを終了させる)。解決しない Promise は、WebKit が「到達できない」と扱うので、
// 十分長い待ち時間のあとで解決する。
return new Promise((resolve) => setTimeout(() => resolve("driver timeout"), 10 * 60 * 1000));
