// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Yasuo Hojo

/// The text scrolled in the About window. Inline Markdown (`code`, *emphasis*) is allowed in the strings.
enum AboutBlock: Sendable {
    case tagline(String)
    case heading(String)
    /// Lines that belong together (shown on separate lines).
    case lines([String])
    case paragraph(String)
    case quote(String)
    case finale
}

struct AboutChapter: Sendable {
    let blocks: [AboutBlock]
}

enum AboutContent {
    static let chapters: [AboutChapter] = [
        AboutChapter(blocks: [
            .tagline("Machines change. Fingers remember.")
        ]),
        AboutChapter(blocks: [
            .heading("1970s — It Began with Macros"),
            .paragraph("At MIT's Artificial Intelligence Laboratory, hackers worked with a line editor called TECO."),
            .paragraph("But they were never content to use a tool exactly as it came."),
            .paragraph("They wrote their own commands, bound them to keys, shared macros, and made them better."),
            .paragraph("TECMAC. TMACS."),
            .paragraph(
                "Eventually, Guy Steele and Richard Stallman set out to bring the best of these ideas together."),
            .paragraph("In 1976, EMACS was born."),
            .paragraph("*Editor MACroS.*"),
            .paragraph("At first, it really was a collection of macros."),
        ]),
        AboutChapter(blocks: [
            .heading("1976 — From Thought to Fingertips"),
            .paragraph("Emacs became more than a way to edit text."),
            .lines(["Move the cursor.", "Find a word.", "Switch buffers.", "Split a window."]),
            .paragraph("All without leaving the keyboard."),
            .paragraph("With practice, the commands no longer needed conscious thought."),
            .paragraph("Fingers moved. The screen responded."),
            .paragraph("Actions became muscle memory, then faded from awareness."),
            .paragraph("The tool became transparent."),
        ]),
        AboutChapter(blocks: [
            .heading("1980s — James Gosling and the Editor He Couldn't Forget"),
            .paragraph("James Gosling, who would later create Java, was another hacker captivated by Emacs."),
            .paragraph("He had used Emacs on Multics. Then he returned to Unix."),
            .paragraph("There, he found ed and vi."),
            .paragraph("But he missed Emacs."),
            .paragraph("So he built his own."),
            .paragraph("Gosling Emacs was born."),
            .paragraph(
                "He also devised a clever screen-redrawing algorithm using dynamic programming, making display updates more efficient on slow terminals."
            ),
            .paragraph("Because responsiveness matters."),
            .paragraph("A screen that keeps up with your fingers helps your thoughts keep flowing."),
        ]),
        AboutChapter(blocks: [
            .heading("1985 — GNU Emacs"),
            .paragraph("Richard Stallman's GNU Emacs arrived."),
            .paragraph("A tool its users could understand, modify, and extend."),
            .paragraph("Emacs Lisp took that freedom even further."),
            .paragraph("And generation after generation of hackers kept Emacs growing."),
            .paragraph("Machines changed. Operating systems changed."),
            .paragraph("The keystrokes stayed in their fingers."),
        ]),
        AboutChapter(blocks: [
            .heading("2004 — Markdown"),
            .paragraph("John Gruber introduced Markdown, with help from Aaron Swartz."),
            .paragraph("It brought people closer to text from another direction."),
            .paragraph("See `#`, and you recognize a heading."),
            .paragraph("See `-`, and a list begins to take shape."),
            .paragraph("Wrap a word in `*asterisks*`, and emphasis feels almost self-explanatory."),
            .paragraph("The meaning is visible before you've even learned the syntax."),
            .paragraph("No special editor. No elaborate formatting controls."),
            .paragraph("Just plain text that already reads like a document."),
            .paragraph("Markdown cleared away some of the distance between expression and meaning."),
        ]),
        AboutChapter(blocks: [
            .heading("Where Two Ideas Meet"),
            .paragraph("Emacs reduced the friction of interaction."),
            .paragraph("Markdown reduced the friction of reading and writing."),
            .paragraph("One began at the fingertips."),
            .paragraph("The other, at the eyes."),
            .paragraph("Perhaps both were reaching for the same thing:"),
            .quote("Never interrupt a human thought just to satisfy the tool."),
        ]),
        AboutChapter(blocks: [
            .heading("hyperbuf — A Natural Way to Read"),
            .paragraph("The muscle memory of Emacs."),
            .paragraph("The intuitive clarity of Markdown."),
            .paragraph("We wanted to bring them together on modern macOS."),
            .paragraph(
                "Move between buffers. Switch windows. Navigate a world of documents without losing your train of thought."
            ),
            .paragraph("Find what you need, with just the effort it deserves."),
            .paragraph("Let the controls disappear, and focus on reading."),
            .paragraph("Not another tool you have to learn from scratch."),
            .paragraph("Something that feels as familiar as an old favorite."),
            .paragraph("That is what hyperbuf aims to be."),
        ]),
        AboutChapter(blocks: [
            .heading("With Respect and Gratitude"),
            .paragraph("To TECO, Emacs, and GNU Emacs."),
            .paragraph("To Markdown and the culture of plain text."),
            .paragraph("And to every hacker who created, preserved, and carried these ideas forward:"),
            .paragraph("Thank you."),
        ]),
        AboutChapter(blocks: [.finale]),
    ]
}
