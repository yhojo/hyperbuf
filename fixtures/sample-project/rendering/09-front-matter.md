---
title: YAML front matter
status: draft
date: 2026-11-26
tags: [rendering, yaml, front-matter]
authors:
  - name: Alice
    role: writer
  - name: Bob
    role: reviewer
review:
  required: true
  approvers: 2
summary: >
  A folded scalar that spans
  several lines in the source.
html: "<b>not bold</b> <script>alert(1)</script>"
empty:
---

# YAML front matter

The block at the start of this file is shown as a table with one row per key. Nested mappings become nested
tables, a list of mappings (`authors`) becomes a table with one row per item, and a list of plain values
(`tags`) stays on one line.

- `html` shows its value as text (nothing in front matter is interpreted as HTML or Markdown).
- `empty` has no value and shows an empty cell.

A `---` block that is not at the very start of the file stays ordinary Markdown:

---
not: front matter
---

Back: [index](00-index.md)
