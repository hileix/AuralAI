# Merge GrammarFix Into AuralAI Plan

## Goal

Merge the GrammarFix macOS menu bar app into the current AuralAI macOS app so one app can:

- read selected text aloud with the existing AuralAI TTS workflow
- improve/translate selected text with the GrammarFix AI workflow
- expose both workflows from one menu bar app and one settings window

## Assumptions

- AuralAI remains the primary app target, bundle, app name, Core Data store, and packaging flow.
- GrammarFix is merged as a feature set, not kept as a second Xcode target or nested app.
- Existing AuralAI TTS behavior should keep working unless a change is required for the merge.
- The two hotkeys should remain separate by default:
  - AuralAI TTS: current AuralAI default
  - GrammarFix: Option+E
- GrammarFix API credentials stay local in `UserDefaults`; no API keys should be committed.

## Source Mapping

Current app:

- `AuralAI/AuralAIApp.swift`: app entry point, menu bar app delegate, TTS hotkey workflow
- `AuralAI/Models/SpeechSettings.swift`: TTS voice and hotkey settings
- `AuralAI/Services/GlobalHotkeyService.swift`: current TTS hotkey and copy simulation
- `AuralAI/Services/ClipboardMonitor.swift`: pasteboard access
- `AuralAI/Views/SettingsView.swift`: existing settings UI

GrammarFix source:

- `GrammarFix/GrammarFix/GrammarFix/GrammarFixApp.swift`: GrammarFix app lifecycle and workflow
- `GrammarFix/GrammarFix/GrammarFix/Models/AppSettings.swift`: AI prompt/API/hotkey settings
- `GrammarFix/GrammarFix/GrammarFix/Services/VertexAIService.swift`: API calls and response parsing
- `GrammarFix/GrammarFix/GrammarFix/Services/FloatingIndicator.swift`: loading/result popup
- `GrammarFix/GrammarFix/GrammarFix/Services/ClipboardService.swift`: pasteboard helper
- `GrammarFix/GrammarFix/GrammarFix/Services/GlobalHotkeyService.swift`: GrammarFix hotkey/copy/paste
- `GrammarFix/GrammarFix/GrammarFix/Views/SettingsView.swift`: GrammarFix settings UI

## Integration Strategy

1. Preserve AuralAI as the only app entry point.
   - Do not copy `@main GrammarFixApp`.
   - Move the GrammarFix workflow into AuralAI's existing `AppDelegate`.

2. Avoid type-name conflicts by renaming imported GrammarFix types.
   - `AppSettings` -> `GrammarSettings`
   - `VertexAIService` -> `GrammarAIService`
   - `AIResponse` -> `GrammarAIResponse`
   - `FloatingIndicator` -> `GrammarFloatingIndicator`
   - GrammarFix `SettingsView` -> `GrammarSettingsView` or a settings section view
   - GrammarFix `GlobalHotkeyService` -> `GrammarHotkeyService`

3. Keep hotkey services separate for the first merge.
   - This avoids risky refactoring of the existing AuralAI hotkey behavior.
   - Reuse the safer status-checking and stale-clipboard protections already added to AuralAI where practical.
   - Use a distinct Carbon hotkey signature/id for GrammarFix.
   - Filter each Carbon event by `EventHotKeyID` before triggering callbacks, or replace both services with one shared dispatcher.

4. Share clipboard behavior carefully.
   - Reuse AuralAI's existing `ClipboardMonitor` read/write/change-count helpers.
   - Add only paste simulation to the grammar hotkey service.
   - For the grammar workflow, compare pasteboard `changeCount` after simulated copy to avoid improving stale clipboard text.

5. Add GrammarFix workflow to `AuralAIApp.AppDelegate`.
   - Keep existing TTS callback unchanged.
   - Add a GrammarFix callback:
     - dismiss any existing grammar popup
     - capture frontmost source app
     - simulate copy
     - wait briefly
     - read new clipboard text only if the pasteboard changed
     - call `GrammarAIService`
     - show selectable results in `GrammarFloatingIndicator`
     - write selected result to clipboard
     - reactivate source app
     - paste selected result

6. Merge settings UI without replacing current settings.
   - Add a settings layout that contains both Speech and Grammar sections.
   - Prefer tabs if the combined form becomes too long:
     - Speech tab: existing AuralAI settings
     - Grammar tab: API mode, model, base URL, API key, max tokens, system prompt, grammar hotkey
   - Keep the existing explicit Save flow.

7. Update project configuration.
   - Add the new Swift files to the AuralAI target.
   - Do not add the nested `GrammarFix.xcodeproj` as a dependency.
   - Keep generated Info.plist keys in the AuralAI target.
   - Review entitlements:
     - AuralAI is currently sandboxed.
     - GrammarFix is not sandboxed.
     - If sandbox stays enabled, add outbound network entitlement for AI API calls.

8. Update documentation and cleanup.
   - Update `README.md` with the new grammar workflow, settings, API requirements, and permissions.
   - Keep `GrammarFix/` as reference during implementation.
   - After the merge is verified, decide whether to remove the nested cloned repo from the working tree.

## Required Pre-Merge Fixes

- Add Carbon hotkey event filtering.
  - Current AuralAI and GrammarFix handlers both listen for `kEventHotKeyPressed`.
  - Before two hotkey services coexist, each handler must inspect `EventHotKeyID` and ignore events it does not own, or both workflows may run from one shortcut event.
  - Alternative: replace both services with one shared hotkey dispatcher.

- Prefix all GrammarFix settings keys.
  - GrammarFix's current `hotkeyKey` and `hotkeyModifiers` keys collide with AuralAI's `SpeechSettings`.
  - Use namespaced keys such as `grammar.systemPrompt`, `grammar.apiKey`, `grammar.hotkeyKey`, and `grammar.hotkeyModifiers`.
  - Do this before wiring `GrammarSettings.shared` into the merged app.

- Add network entitlement if sandbox remains enabled.
  - AuralAI is sandboxed and currently lacks `com.apple.security.network.client`.
  - GrammarFix needs outbound API access, so the merged app needs the network client entitlement unless sandboxing is intentionally removed.

- Remove `TextSelectionMonitor` from merge scope unless it gets real behavior.
  - The cloned GrammarFix implementation is currently a no-op.
  - Do not copy it just to preserve structure; add it only if selection monitoring is implemented and manually verified.

## Implementation Phases

1. Add GrammarFix model and services under AuralAI.
   - Copy and rename GrammarFix settings, AI service, and floating indicator.
   - Prefix all GrammarFix `UserDefaults` keys.
   - Add paste support to the grammar hotkey service.
   - Add Carbon `EventHotKeyID` filtering to both the existing AuralAI hotkey handler and the new grammar hotkey handler, or replace both with one shared dispatcher.
   - Verify: project builds.

2. Wire the grammar workflow into the AuralAI app delegate.
   - Add service properties and callback setup.
   - Add stale-clipboard protection.
   - Verify: existing TTS workflow is still structurally unchanged and project builds.

3. Merge settings UI.
   - Add a grammar settings view or tab.
   - Keep current speech settings fields intact.
   - Verify: settings compile and both settings models save independently.

4. Update target configuration and entitlements.
   - Add new files to the AuralAI target.
   - Add `com.apple.security.network.client` if sandbox remains enabled.
   - Verify: generated app metadata and entitlements match expected runtime needs.

5. Update docs.
   - Document both hotkeys, AI configuration, permissions, and packaging.
   - Verify: README matches the merged app behavior.

## Risks

- Two global hotkeys can conflict if the user configures the same shortcut for both workflows.
- Without `EventHotKeyID` filtering, two Carbon handlers may both respond to one hotkey event.
- Sandbox settings may block API calls unless the network entitlement is added or sandboxing is revisited.
- Unprefixed GrammarFix `UserDefaults` keys may overwrite AuralAI speech settings.
- The GrammarFix API body includes provider-specific fields; some OpenAI-compatible endpoints may reject them.
- Clipboard-based workflows can still fail in apps that block simulated copy/paste.
- Settings UI may become crowded if both apps' forms are simply appended.

## Verification Plan

- Build the AuralAI scheme.
- Manually verify:
  - app launches as one menu bar app
  - AuralAI TTS hotkey still speaks selected text
  - GrammarFix hotkey captures selected text, calls the configured API, shows options, and pastes the selected result
  - both hotkeys can be changed and persisted
  - changing and saving Grammar settings, then restarting, does not change Speech settings
  - accessibility prompt/retry still works
  - settings changes do not apply until Save
- Optional after manual verification:
  - run existing unit/UI tests if desired
  - package DMG with `Scripts/package_dmg.sh`
