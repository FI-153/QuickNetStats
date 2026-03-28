# QuickNetStats — Code Style Guide

## Linting

SwiftLint is configured via `.swiftlint.yml` at the project root. It runs automatically as an
Xcode Build Phase on every build.

```bash
# Lint
swiftlint lint

# Auto-fix violations
swiftlint lint --fix
```

### Key SwiftLint rules

- `trailing_whitespace` and `opening_brace` are **disabled** to match existing code style.
- Line length: warning at 160, error at 250.
- Identifiers: minimum 2 chars, `_` allowed in names, `id` and `ip` excluded.
- Type body length: warning at 400, error at 600.

## Naming Conventions

- **Types** (structs, classes, enums, protocols): `UpperCamelCase`
- **Properties, methods, variables**: `lowerCamelCase`
- **Constants**: `lowerCamelCase` (Swift convention, not `SCREAMING_SNAKE`)
- **Enum cases**: `lowerCamelCase`
- **Files**: match the primary type name (e.g., `NetworkStats.swift`)
- **SwiftUI views**: suffix with `View` (e.g., `NetStatsView`, `AddressView`)
- **ViewModels**: suffix with `ViewModel` (e.g., `NetStatsViewModel`)
- **Managers**: suffix with `Manager` (e.g., `NetworkStatsManager`)

## Import Organization

1. System/Apple frameworks (`Foundation`, `SwiftUI`, `Network`, `Combine`, etc.)
2. No external dependencies in this project

Avoid duplicate imports in the same file.

## Documentation

- Add `///` doc comments for public APIs and non-trivial logic.
- Use `// MARK: -` sections to organize types (Properties, Computed Properties, Initializers, etc.).
- Inline comments for complex business logic (e.g., hotspot reclassification).

## SwiftUI Patterns

- Use `@StateObject` for owned observable objects created at the declaration site.
- Use `@ObservedObject` for observable objects passed in from a parent.
- Use `@EnvironmentObject` for app-wide dependencies (e.g., `Settings`).
- Use `@Environment(\.keyPath)` for system-provided values (e.g., `openWindow`).
- Add `#Preview` blocks to view files for SwiftUI previews using static mock data.

## Architecture — MVVM

- **Models**: plain value types or `ObservableObject`s for data.
- **ViewModels**: contain presentation logic, expose `@Published` properties.
- **Views**: declarative SwiftUI, minimal logic — delegate to ViewModels.
- **Managers**: observable business logic, injected as `@StateObject` from the app entry point.

## Accessibility

- Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` for animations.

## Concurrency

- Network monitor callbacks run on a dedicated background `DispatchQueue`.
- Always dispatch UI updates to the main thread via `DispatchQueue.main.async`.
- Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting.
- Use `async/await` for network calls (e.g., public IP fetching).

## Platform Guards

- Features requiring macOS 26+ (e.g., `NWPath.linkQuality`) must be guarded with
  `if #available(macOS 26, *)`.
