// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

// Driver for integration tests (IPC) (runs inside the WebView).
// Answers the minibuffer's "open a warn-path file?" automatically, by the name of the path:
//  a path containing /approve/ or /urlconf/ -> yes, /deny/ -> no, /wait/ -> no answer (to check that it closes on timeout).
// What it answered is recorded in the test log as `ANSWERED <heading>`.
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
  if (label.includes("/approve/") || label.includes("/urlconf/")) {
    window.hyperbufHost.log("ANSWERED " + label);
    type("yes");
    press("Enter", "Enter");
  } else if (label.includes("/deny/")) {
    window.hyperbufHost.log("ANSWERED " + label);
    type("no");
    press("Enter", "Enter");
  } else if (label.includes("/wait/")) {
    // No answer. When the request's deadline passes, the app should close this confirmation (record that it closed in the test log)
    window.hyperbufHost.log("SAW wait prompt");
    const watch = setInterval(() => {
      if (document.getElementById("minibuffer").hidden) {
        window.hyperbufHost.log("HIDDEN wait prompt");
        clearInterval(watch);
      }
    }, 50);
  }
}, 50);
// When this script finishes, the harness quits the app. Do not finish before the test ends (normally the shell script
// quits the app first). WebKit treats a never-resolving Promise as "unreachable", so
// resolve it after a sufficiently long wait.
return new Promise((resolve) => setTimeout(() => resolve("driver timeout"), 10 * 60 * 1000));
