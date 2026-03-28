# Context Folder Guide

This folder provides background knowledge, style rules, and agent plans for the QuickNetStats
project. Claude Code loads this file automatically when accessing any file under `context/`.

## Folder Map

```
context/
├── knowledge/     API references, architecture docs, research
├── styling/       Code style rules (SwiftLint config, naming, patterns)
└── planning/      Agent-written plans for user review before implementation
```

---

## `knowledge/` — Read before writing or modifying code

_(No documents yet — add API references, architecture docs, and research here as needed.)_

---

## `styling/` — Read before writing any new code

- [`formatting.md`](styling/formatting.md) — the project style guide: SwiftLint config, naming
  conventions, import order, SwiftUI patterns, MVVM architecture, accessibility. This is the
  authoritative source; always defer to it over your own defaults.

  When implementing new methods always add docstrings in accordance to the directives under
  the context/styling guidelines.

---

## `planning/` — Agent-written plans

- Before implementing any non-trivial task, write a plan here and wait for user approval.
- File names must be descriptive kebab-case (e.g., `add-notification-categories.md`).
- Plans are committed to git and never deleted — they serve as historical documentation.
- User review comments inside plan files are preceded by `/user`.
- When new additions to the plan are made in response to comments mark them with `/new`.
- Delete all the `/new` already present in a plan when updating it or adding the todo list.
- Always ask ANY clarifying questions you need to create a plan, avoid assumptions if not asked
  to do otherwise.
- After you add or modify the contents of a file execute `swiftlint lint` and address formatting and
  linting issues.
- Once a plan is approved, follow the checklist in order and check each box (`- [x]`) in the plan
  file immediately upon completing the corresponding task.
