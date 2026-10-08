# コード

## Python

```python
from dataclasses import dataclass

@dataclass
class Buffer:
    path: str
    text: str = ""

    def lines(self) -> list[str]:
        return self.text.splitlines()  # 行に分ける
```

## JavaScript

```js
export function visit(model, win, path, anchor = null) {
  const cur = currentEntry(win);
  if (cur?.path === path && cur.anchor === anchor) return;
  win.history.splice(win.index + 1);
}
```

## TypeScript

```ts
type Entry = { path: string; anchor: string | null; scroll: number };
const entries: Entry[] = [];
```

## Swift

```swift
final class Host: NSObject, WKURLSchemeHandler {
    static let scheme = "hyperbuf"
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {}
}
```

## Rust

```rust
fn contained(root: &Path, rel: &str) -> Result<PathBuf, String> {
    let file = root.join(rel).canonicalize().map_err(|e| e.to_string())?;
    Ok(file)
}
```

## Go

```go
func main() {
	fmt.Println("hello")
}
```

## Emacs Lisp

```elisp
(defun hyperbuf-open (file &optional line)
  "Open FILE in Hyperbuf."
  (interactive "fFile: ")
  (call-process "hyperbuf" nil 0 nil file))
```

## Shell と diff

```bash
git switch -c docs/example && echo "done"
```

```diff
- old line
+ new line
```

## JSON / YAML / HTML / CSS

```json
{ "name": "hyperbuf", "private": true, "scripts": { "build": "node build.mjs" } }
```

```yaml
name: hyperbuf
items:
  - a
  - b
```

```html
<div class="x" onclick="alert(1)">text</div>
```

```css
.markdown-body { background: transparent; }
```

## 言語指定なし・未知の言語

```
plain text block
```

```nosuchlang
unknown language block
```
