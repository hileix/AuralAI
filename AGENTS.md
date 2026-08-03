# Repository Guidelines

## Project Structure & Module Organization

- `AuralAI/` contains the macOS menu bar app. Keep SwiftUI screens in `Views/`, data/settings types in `Models/`, and system integrations in `Services/`.
- `AuralAI/AuralAIApp.swift` wires app lifecycle, global shortcuts, focused text input, grammar requests, and UI coordination.
- `AuralAITests/` contains unit tests using Swift Testing. `AuralAIUITests/` contains macOS UI tests using XCTest.
- `AuralAI/Assets.xcassets/` stores app icons and images. Core Data models live in `AuralAI/AuralAI.xcdatamodeld/`.
- `Scripts/` contains development installation and DMG packaging helpers; generated artifacts belong in `dist/`.

## Build, Test, and Development Commands

Run commands from the repository root:

```bash
xcodebuild -project AuralAI.xcodeproj -scheme AuralAI -destination 'platform=macOS' build
xcodebuild -project AuralAI.xcodeproj -scheme AuralAI -destination 'platform=macOS' -only-testing:AuralAITests test
bash Scripts/install_dev.sh
bash Scripts/package_dmg.sh --clean
```

The first command builds the app, the second runs unit tests, `install_dev.sh` installs a stable development build for Accessibility testing, and `package_dmg.sh` creates a distributable DMG. UI tests can be run from Xcode or by omitting `-only-testing`.

## Coding Style & Naming Conventions

Use four-space indentation, standard Swift naming, and concise types that match the existing structure. Types and protocols use `UpperCamelCase`; methods, properties, and local values use `lowerCamelCase`. Prefer existing services and models over new abstractions. Keep API keys in local `UserDefaults` only; never commit credentials.

## Testing Guidelines

Add focused unit tests for model, persistence, parsing, and workflow changes. Name tests by behavior, such as `grammarHistoryReturnsNewestTrimmedExactMatch`. Add or update UI tests when accessibility identifiers or visible workflows change. Run the unit target before submitting and note any macOS Accessibility or UI-runner limitations.

## Commit & Pull Request Guidelines

Use Conventional Commits in imperative lowercase form, for example `fix: hide the grammar badge for empty inputs` or `feat: reuse cached grammar results`. Keep commits focused. Pull requests should explain the behavior change, list verification commands, link related issues when applicable, and include screenshots for UI changes.

## Security & Configuration Tips

The app relies on unsandboxed macOS Accessibility APIs for global shortcuts and focused-field editing. Test with Accessibility permission enabled. Signing and Developer ID settings are configured in Xcode; do not weaken entitlements or commit private signing material.
