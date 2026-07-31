# AuralAI

AuralAI is a SwiftUI menu bar app for text-to-speech and AI grammar improvement.

It reads the current selection for text-to-speech, detects focused text fields for whole-field grammar improvement, and keeps selection-based grammar improvement as a compatibility fallback.

## Current Features

- Global hotkey on macOS for reading selected text
- Separate grammar improvement hotkey, defaulting to `Ctrl+E`
- Focused text field detection with an AuralAI action button near the field
- Customizable shortcut key and modifier combination
- English voice selection with live preview
- Adjustable speech rate and pitch
- AI settings for API mode, model, base URL, API key, max tokens, and system prompt
- Selectable grammar/translation results that can be pasted back into the source app
- Settings UI in English and Chinese
- Explicit save flow in settings
- Speech history stored with Core Data

## macOS Flow

AuralAI on macOS is a `MenuBarExtra` app.

1. Launch the app.
2. Open `Settings` from the menu bar.
3. Choose the speech shortcut, language, voice, rate, and pitch.
4. Click `Save` to persist changes.
5. Select text in any app.
6. Press the configured hotkey.

When the hotkey is pressed, AuralAI simulates `Cmd+C`, reads the copied text from the pasteboard, and speaks it aloud.

For grammar improvement:

1. Open the `Grammar` tab in Settings.
2. Enter the API mode, model, base URL, API key, max tokens, and system prompt.
3. Click `Save`.
4. Focus a supported text field in another app. AuralAI shows its logo near the field.
5. Click the logo or press the grammar hotkey, defaulting to `Ctrl+E`. AuralAI reads the selected text when a selection exists, or the entire field when there is no selection.
6. Choose one result from the popup to replace the selected range or the entire field, matching what was improved.

When the focused app does not expose a supported text field through macOS Accessibility, the existing selection workflow remains available:

1. Select text in any app.
2. Press the grammar hotkey.
3. Choose one result from the popup to copy it to the pasteboard and paste it back into the source app.

The app requires Accessibility permission on macOS so it can:

- register a global hotkey
- simulate `Cmd+C` to capture selected text
- simulate `Cmd+V` to paste a selected grammar result
- detect and read focused text fields in other apps

## Settings

The settings window has `Speech` and `Grammar` tabs.

The Speech tab supports:

- one-key shortcut input plus a modifier-combination picker
- English or Chinese UI language
- English voice selection
- default voice fallback that prefers higher-quality English voices
- speech rate and pitch controls
- a `Test Speech` preview button
- a `Reset to Defaults` action

The Grammar tab supports:

- grammar shortcut key and modifier combination
- OpenAI-compatible or direct API mode
- model, base URL, API key, max tokens, and system prompt
- resetting grammar settings to defaults

Changes in the settings window are edited as a draft and are only applied after clicking `Save`. Saving does not close the window.

## Data Storage

Speech settings are stored in `UserDefaults`:

- keys: `voiceIdentifier`, `rate`, `pitch`, `language`, `hotkeyKey`, `hotkeyModifiers`

Grammar settings are stored in `UserDefaults` with `grammar.`-prefixed keys, including `grammar.apiKey`. API keys stay local and should not be committed.

Speech history is stored in Core Data.

## Project Structure

- `AuralAI/`: app source
- `AuralAI/Models/`: settings and model types
- `AuralAI/Services/`: hotkey, clipboard, and TTS services
- `AuralAI/Views/`: SwiftUI views
- `AuralAITests/`: unit tests
- `AuralAIUITests/`: UI tests

## Requirements

- Xcode
- macOS for the menu bar hotkey workflow
- Apple signing configured in Xcode if you want to build and run directly from the project

## Build

Open `AuralAI.xcodeproj` in Xcode and run the `AuralAI` scheme.

If Xcode reports a signing error, update the team and signing certificate in the project settings before building.

## Install a Development Build

For repeated Accessibility testing, install a Release-like development build at the same app path:

```bash
bash Scripts/install_dev.sh
```

The script builds `AuralAI Dev.app` with the fixed bundle identifier `com.xiaolei.AuralAI.dev`, disables debug signing entitlements, updates `/Applications/AuralAI Dev.app` in place, and launches it. After using this script for the first time, macOS may require one final off/on toggle for `AuralAI Dev` under **System Settings > Privacy & Security > Accessibility**.

The script uses the signing identity configured in Xcode. A stable Developer ID Application certificate is still required for production-grade permission persistence across distributed builds.

The regular Xcode Debug build uses `AuralAI Debug` and `com.xiaolei.AuralAI.debug`. Keeping that temporary build identity separate prevents Xcode's DerivedData apps from conflicting with the installed `AuralAI Dev` Accessibility entry.

AuralAI is intentionally unsandboxed because its focused-field workflow uses macOS Accessibility APIs to inspect and update text in other apps. This system-wide capability is not available to an App Sandbox assistive app, so distribution should use Developer ID signing and notarization rather than Mac App Store sandboxing.

## DMG Packaging

To build a distributable macOS app bundle and package it into a DMG:

```bash
bash Scripts/package_dmg.sh --clean
```

By default the script uses `xcodebuild archive`, copies the archived `AuralAI.app` into `dist/`, and creates `dist/AuralAI.dmg`.
The generated DMG includes a standard drag-to-install layout with `AuralAI.app` and an `Applications` shortcut.

Useful variants:

```bash
bash Scripts/package_dmg.sh --mode build
bash Scripts/package_dmg.sh --configuration Debug --build-dir out
```

If signing is not configured correctly in Xcode, the script will fail during the `xcodebuild` step.
If Finder automation is blocked by system permissions, the script still creates a usable drag-install DMG, but the icon layout may fall back to the default arrangement.

## License

This project is licensed under the MIT License. See `LICENSE` for details.
