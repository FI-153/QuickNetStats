# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Policy

**Never commit code autonomously.** Always wait for the user to explicitly ask for a commit before running any `git commit`, `git add`, or `git push` commands.

## Project Overview

QuickNetStats is a **macOS menu bar application** that displays real-time network statistics (connection type, link quality, IP addresses). It uses `MenuBarExtra` with `.window` style for the popover UI and a separate `Window` scene for settings.

## Build & Run

This is a native Xcode project (no SPM, CocoaPods, or external dependencies).

```bash
# Build
xcodebuild -project QuickNetStats.xcodeproj -scheme QuickNetStats -configuration Debug build

# Build for release
xcodebuild -project QuickNetStats.xcodeproj -scheme QuickNetStats -configuration Release build
```

### Testing

Tests use **Swift Testing** framework (`import Testing`). The test target is `QuickNetStatsTests`.

```bash
# Run all tests
xcodebuild test -project QuickNetStats.xcodeproj -scheme QuickNetStats -destination 'platform=macOS'
```

Verify changes by building successfully, running tests, and checking SwiftUI previews.

### Linting

```bash
# Lint
swiftlint lint

# Auto-fix violations
swiftlint lint --fix
```

Configuration is in `.swiftlint.yml`. `trailing_whitespace` and `opening_brace` rules are disabled to match the existing code style.

## Requirements

- macOS 13.0+ (Ventura) deployment target
- Xcode 15.0+ with Swift 5.9
- macOS 26.0 (Tahoe) required for `NWPath.linkQuality` API (guarded with `#available(macOS 26, *)`)

## Architecture

**MVVM** with SwiftUI, using `@StateObject`/`@ObservedObject` for state and `@EnvironmentObject` for settings propagation.

### App Entry Point

`QuickNetStatsApp` creates two scenes:
1. `MenuBarExtra` - the main popover showing network stats
2. `Window("Settings")` - a standalone settings window opened via `openWindow(id:)`

Three root-level `@StateObject`s are created in the app struct: `NetworkStatsManager`, `NetworkDetailsManager`, and `Settings`.

### Managers (observable business logic)

- **`NetworkStatsManager`** - Wraps `NWPathMonitor` on a background `DispatchQueue`, publishes `NetworkStats` snapshots. Handles monitor lifecycle (start/stop/refresh) since `NWPathMonitor` can only be started once.
- **`NetworkDetailsManager`** - Fetches private IP (via `SCNetworkInterfaceCopyAll`) and public IP (via ipify API with async/await).
- **`NotificationsManager`** - Singleton (`.shared`) that compares old vs new `NetworkStats` to fire `UNUserNotification`s based on user preferences.
- **`StartAtLoginManager`** / **`UpdateManager`** - Login item and update checking utilities.

### Models

- **`NetworkStats`** - Value type built from `NWPath`. Determines `NetworkInterfaceType` (.wifi/.ethernet/.cellular/.other/.none) and `LinkQuality` (.good/.moderate/.minimal/.unknown). Hotspot connections over WiFi/Ethernet are reclassified as `.cellular` when `path.isExpensive` is true.
- **`Settings`** - `ObservableObject` using `@AppStorage` for all preferences (menu bar display, animations, notifications). Passed via `@EnvironmentObject`.
- **`Notification`** - Notification model for the notification system.

### Views

- `ContentView` - Root view composing `NetStatsView` + footer/header buttons
- `NetStatsView` / `NetStatsViewModel` - Main display of connection status, quality, and IP addresses
- `SettingsView` / `SettingsViewModel` - Settings tabs (MenuBar, Visuals, Notifications, About)
- `Views/Camponents/` - Reusable components (note: directory is intentionally spelled "Camponents")

## Key Patterns

- **Main thread dispatch**: Network monitor callbacks dispatch UI updates to main thread via `DispatchQueue.main.async`
- **Default actor isolation**: Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting
- **Accessibility**: Animation settings respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
- **Bundle IDs**: `com.federicoimberti.quicknetstats.dev` (debug) / `com.federicoimberti.quicknetstats` (release)
- **Static mockups**: `NetworkStats` has static mock properties (e.g., `mockGoodWifiCoonection`) used for SwiftUI previews

## CI/CD

GitHub Actions workflow (`.github/workflows/release.yml`) triggers on release publication to update the Homebrew tap at `FI-153/homebrew-tap`. It detects beta vs stable releases from the tag name and updates the appropriate cask file.

## Planning Workflow

Whenever the user asks Claude to plan a task, Claude **must** write the plan as a `.md` file inside
`context/planning/` before doing any implementation work. File names must be descriptive kebab-case
(e.g., `add-metrics-extraction.md`). After writing the plan, Claude notifies the user of the file
path and waits for explicit approval before proceeding. The user may edit the plan file directly
using `/user <comment>` annotations; When new additions to the plan are made in response to comments
mark them with `/new`; Delete all the `/new` already present in a plan when updating or adding the
todo list; implementation begins only after the user explicitly approves; Plans are committed to
git alongside code for documentation purposes and are never deleted.

**Asking Questions** ALWAYS ask any clarifying questions you need and avoid assumptions unless
asked otherwise.

**Important**: When writing a plan, include ONLY the architectural design and approach — no
implementation checklists or checkboxes. The user will ask for implementation steps separately
after approving the plan. Do not add execution details, step numbering, or checkbox lists unless
the user explicitly requests them.

**Single file per task**: The design spec and the implementation plan must live in the **same file**
in `context/planning/`. The design sections come first, followed by the implementation steps
appended below. Do not create separate files for the design and the plan.

Once a plan is approved and the user asks for implementation steps, Claude must append the
implementation checklist to the same plan file. After implementation begins, Claude must follow the
checklist in order, checking each box (`- [x]`) immediately upon completing the corresponding task.

### Plan file format

```markdown
# Plan: <Descriptive Title>

> **Date**: YYYY-MM-DD
> **Scope**: <what this plan covers>
> **Prerequisite**: <any plans or work that must be done first>

---

## Context

<Why this work is needed. What exists today. What gap this fills.>

---

## Overview

<High-level architecture diagram (ASCII or Mermaid) showing components and data flow.>

---

## Design

<Detailed design: new modules, classes, methods, data models, protocols.
Reference existing code patterns where relevant.>

---

## Edge Cases & Constraints

<Known limitations, error scenarios, performance considerations.>
```

### Comment and annotation conventions

| Marker | Meaning |
|--------|---------|
| `/user <comment>` | User-written feedback inside the plan file |
| `/new` | Marks new content added in response to `/user` comments |
| `- [ ]` | Implementation step (added only after user asks for steps) |
| `- [x]` | Completed implementation step |

## Superpowers Plugin

Claude **must** use the `superpowers` skill set for structured development work:

- **Brainstorming** (`superpowers:brainstorm`): Use before any creative work — creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements, and design before implementation.
- **Writing Plans** (`superpowers:writing-plans`): Use when there is a spec or requirements for a multi-step task, before touching code. Produces a structured plan in `context/planning/`.
- **Executing Plans** (`superpowers:executing-plans`): Use when there is a written implementation plan to execute, with review checkpoints.
- **Systematic Debugging** (`superpowers:systematic-debugging`): Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes.
- **Dispatching Parallel Agents** (`superpowers:dispatching-parallel-agents`): Use when facing 2+ independent tasks that can be worked on without shared state.
- **Code Review** (`superpowers:requesting-code-review`): Use when completing tasks or implementing major features to verify work meets requirements.
- **Verification** (`superpowers:verification-before-completion`): Use when about to claim work is complete — run verification commands and confirm output before making success claims.

## Specialized Skills

- **SwiftUI Expert** (`swiftui-expert:swiftui-expert-skill`): Use when planning, writing, reviewing, or improving SwiftUI views. Must be invoked before creating new views or refactoring existing ones.
- **Swift Testing Expert** (`swift-testing-expert:swift-testing-expert`): Use when writing, reviewing, or migrating tests. Must be invoked before creating new test files or modifying existing tests.

## Formatting and Project Structure

See [`context/styling/formatting.md`](context/styling/formatting.md) for the rules to follow
when writing and formatting code in order to conform to the project's standards.
