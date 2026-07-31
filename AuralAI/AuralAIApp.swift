//
//  AuralAIApp.swift
//  AuralAI
//
//  Created by mac on 2026/3/21.
//

import SwiftUI
import OSLog

@main
struct AuralAIApp: App {
    let persistenceController = PersistenceController.shared

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("AuralAI", systemImage: "speaker.wave.2.fill") {
            Button("Settings") {
                appDelegate.openSettingsFromMenuBar()
            }

            Divider()

            Button("Exit") {
                appDelegate.quitFromMenuBar()
            }
        }
        #else
        // iOS: Standard window-based app
        WindowGroup {
            MainView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        #endif
    }
}

#if os(macOS)
/// App delegate for handling macOS-specific functionality
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.xiaolei.AuralAI", category: "GrammarWorkflow")
    private var settingsWindow: NSWindow?

    private let hotkeyService = GlobalHotkeyService.shared
    private let grammarHotkeyService = GrammarHotkeyService.shared
    private let clipboardMonitor = ClipboardMonitor.shared
    private let ttsService = TTSService.shared
    private let grammarAIService = GrammarAIService.shared
    private let grammarIndicator = GrammarFloatingIndicator.shared
    private let focusedTextInputService = FocusedTextInputService.shared
    private let grammarInputBadge = GrammarInputBadge.shared
    private let grammarHistoryStore = GrammarHistoryStore.shared
    private let settings = SpeechSettings.shared
    private let grammarSettings = GrammarSettings.shared
    private let persistenceController = PersistenceController.shared
    private var grammarSourceApp: NSRunningApplication?
    private var grammarSourceInput: FocusedTextInput?
    private var grammarSourceSelection: FocusedTextSelection?
    private var grammarRequestAnchor: NSPoint?
    private var grammarRequestTask: Task<Void, Never>?
    private var grammarRequestID: UUID?
    private var grammarResultsRequestID: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 AuralAI applicationDidFinishLaunching")
        observeSettings()
        setupHotkeyHandler()
        setupGrammarHotkeyHandler()
        setupFocusedTextInputHandler()
        setupAccessibilityPermissionHandler()
        checkAccessibilityPermissions()
        focusedTextInputService.start()

        #if DEBUG
        if CommandLine.arguments.contains("--auralai-ui-test-open-settings") {
            DispatchQueue.main.async {
                self.openSettings()
            }
        }

        configureUITestAppearanceIfNeeded()
        configureGrammarHistoryPreviewIfNeeded()
        showGrammarUIPreviewIfNeeded()
        #endif

        print("✅ AuralAI started. Press \(settings.hotkeyDisplayString) to speak selected text.")
        print("✅ Grammar improvement available with \(grammarSettings.hotkeyDisplayString).")
    }

    #if DEBUG
    private func configureUITestAppearanceIfNeeded() {
        guard let appearance = ProcessInfo.processInfo.environment["AURALAI_UI_TEST_APPEARANCE"] else {
            return
        }

        NSApp.appearance = NSAppearance(
            named: appearance == "dark" ? .darkAqua : .aqua
        )
    }

    private func configureGrammarHistoryPreviewIfNeeded() {
        guard ProcessInfo.processInfo.environment["AURALAI_UI_TEST_HISTORY_PREVIEW"] == "1" else {
            return
        }

        let response = GrammarAIResponse(
            translation: "A focused interface makes everyday work feel effortless.",
            errors: "The original sentence needs an article and more natural word order.",
            options: [
                "A focused interface makes everyday work feel effortless.",
                "Thoughtful design makes routine work feel simple and natural."
            ]
        )
        grammarHistoryStore.usePreviewEntries([
            GrammarHistoryEntry(
                originalText: "Focused interface make everyday work feel effortless.",
                response: response,
                timestamp: Date()
            )
        ])
    }

    private func showGrammarUIPreviewIfNeeded() {
        guard let state = ProcessInfo.processInfo.environment["AURALAI_UI_TEST_GRAMMAR_STATE"] else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let anchor = NSPoint(x: screenFrame.midX, y: screenFrame.midY)

            switch state {
            case "loading":
                self.grammarIndicator.showLoading(at: anchor)
            case "results":
                self.grammarIndicator.showResults(
                    response: GrammarAIResponse(
                        translation: "A focused interface makes everyday work feel effortless.",
                        errors: "The original sentence needs an article and more natural word order.",
                        options: [
                            "A focused interface makes everyday work feel effortless.",
                            "Thoughtful design makes routine work feel simple and natural.",
                            "A clear, polished interface keeps daily tasks moving smoothly."
                        ]
                    ),
                    at: anchor,
                    onSelect: { _ in }
                )
            case "streaming":
                self.grammarIndicator.showStreamingResults(
                    response: GrammarAIResponse(
                        translation: "A focused interface makes everyday work feel effortless.",
                        errors: "The original sentence needs an article and more natural word order.",
                        options: [
                            "A focused interface makes everyday work feel"
                        ]
                    ),
                    onSelect: { _ in },
                    onUserDismiss: {}
                )
            case "badge":
                self.grammarInputBadge.show(
                    for: NSRect(x: anchor.x - 220, y: anchor.y - 70, width: 440, height: 140),
                    onClick: {}
                )
            default:
                break
            }
        }
    }
    #endif

    /// Setup global hotkey handler
    private func setupHotkeyHandler() {
        hotkeyService.onHotkeyTriggered = { [weak self] in
            self?.handleGlobalHotkey()
        }
    }

    /// Setup grammar improvement hotkey handler
    private func setupGrammarHotkeyHandler() {
        grammarHotkeyService.onHotkeyTriggered = { [weak self] in
            self?.handleGrammarGlobalHotkey()
        }
    }

    private func setupFocusedTextInputHandler() {
        focusedTextInputService.onFocusedInputChange = { [weak self] input in
            guard let self else { return }

            guard let input else {
                self.grammarInputBadge.hide()
                return
            }

            self.grammarInputBadge.show(for: input.frame) { [weak self] in
                self?.handleFocusedTextInput(input)
            }
        }
    }

    private func setupAccessibilityPermissionHandler() {
        hotkeyService.onAccessibilityPermissionGranted = { [weak self] in
            guard let self else { return }
            self.grammarHotkeyService.refreshRegistration()
            self.focusedTextInputService.refreshAccessibilityContext()
        }
    }

    /// Check and request accessibility permissions
    private func checkAccessibilityPermissions() {
        #if DEBUG
        if CommandLine.arguments.contains("--auralai-ui-test-open-settings") {
            return
        }
        #endif

        if !hotkeyService.hasAccessibilityPermissions() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.hotkeyService.requestAccessibilityPermissions()
            }
        }
    }

    /// Handle global hotkey press
    @objc private func handleGlobalHotkey() {
        print("\(settings.hotkeyDisplayString) pressed - capturing selected text")

        // Step 1: Simulate Cmd+C to copy selected text
        let previousChangeCount = clipboardMonitor.currentChangeCount()
        guard hotkeyService.copySelectedText() else { return }

        // Step 2: Wait a bit for clipboard to update, then read and speak
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard self.clipboardMonitor.currentChangeCount() != previousChangeCount else {
                print("Clipboard did not change after copy command")
                return
            }

            if let text = self.clipboardMonitor.readClipboardText(), !text.isEmpty {
                print("✅ Text captured from clipboard: \(text.prefix(50))...")
                print("📢 Starting speech synthesis...")

                // Speak the text
                self.ttsService.speak(text: text, settings: self.settings)

                // Save to history
                self.saveSpeechHistory(text: text, source: "hotkey")
            } else {
                print("❌ No text found in clipboard")
            }
        }
    }

    /// Handle grammar improvement hotkey press
    private func handleGrammarGlobalHotkey() {
        if let input = focusedTextInputService.captureCurrentInput() {
            print("\(grammarSettings.hotkeyDisplayString) pressed - capturing the focused input field")
            handleFocusedTextInput(input)
            return
        }

        print("\(grammarSettings.hotkeyDisplayString) pressed - capturing selected text for grammar improvement")

        cancelActiveGrammarRequest()
        grammarIndicator.dismiss()
        grammarSourceApp = NSWorkspace.shared.frontmostApplication
        grammarSourceInput = nil
        grammarSourceSelection = nil
        grammarRequestAnchor = nil

        let previousChangeCount = clipboardMonitor.currentChangeCount()
        guard grammarHotkeyService.copySelectedText() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard self.clipboardMonitor.currentChangeCount() != previousChangeCount else {
                print("Clipboard did not change after grammar copy command")
                self.grammarIndicator.showError()
                return
            }

            guard let text = self.clipboardMonitor.readClipboardText(), !text.isEmpty else {
                print("No text found in clipboard for grammar improvement")
                self.grammarIndicator.showError()
                return
            }

            print("✅ Text captured for grammar improvement: \(text.prefix(50))...")
            self.triggerGrammarImprovement(for: text)
        }
    }

    private func handleFocusedTextInput(_ input: FocusedTextInput) {
        cancelActiveGrammarRequest()
        grammarIndicator.dismiss()

        let badgeAnchor = grammarInputBadge.centerPoint ?? input.anchorPoint
        let sourceSelection = focusedTextInputService.readSelection(from: input)
        grammarSourceInput = input
        grammarSourceSelection = sourceSelection
        grammarSourceApp = NSRunningApplication(processIdentifier: input.processIdentifier)
        grammarRequestAnchor = badgeAnchor
        focusedTextInputService.pause()
        grammarInputBadge.showLoading()

        guard let text = sourceSelection?.text ?? focusedTextInputService.readText(from: input) else {
            logger.error("Failed to read text from focused input pid=\(input.processIdentifier)")
            print("The focused input field does not contain readable text")
            grammarInputBadge.stopLoading()
            grammarIndicator.showError(at: badgeAnchor)
            finishFocusedInputWorkflow(after: 1.5)
            return
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("Focused input text is empty pid=\(input.processIdentifier)")
            print("The focused input field is empty")
            grammarInputBadge.stopLoading()
            grammarIndicator.showError(at: badgeAnchor)
            finishFocusedInputWorkflow(after: 1.5)
            return
        }

        let sourceKind = sourceSelection == nil ? "full" : "selection"
        logger.notice("Captured focused input text source=\(sourceKind, privacy: .public) length=\(text.count) pid=\(input.processIdentifier)")
        print("✅ Focused input text captured: \(text.prefix(50))...")
        triggerGrammarImprovement(for: text, anchor: badgeAnchor, showLoadingIndicator: false)
    }

    private func triggerGrammarImprovement(
        for text: String,
        anchor: NSPoint? = nil,
        showLoadingIndicator: Bool = true
    ) {
        cancelActiveGrammarRequest()

        let requestID = UUID()
        grammarRequestID = requestID
        grammarRequestAnchor = anchor
        if showLoadingIndicator {
            if let anchor {
                grammarIndicator.showLoading(at: anchor)
            } else {
                grammarIndicator.showLoading()
            }
        }

        grammarRequestTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await self.grammarAIService.improveText(text) { [weak self] partialResponse in
                    guard let self, !Task.isCancelled,
                          let parsed = self.grammarAIService.parsePartialResponse(from: partialResponse) else {
                        return
                    }

                    await MainActor.run {
                        guard self.grammarRequestID == requestID else { return }

                        if self.grammarResultsRequestID == requestID {
                            self.grammarIndicator.updateResults(response: parsed, isStreaming: true)
                        } else {
                            self.grammarResultsRequestID = requestID
                            self.grammarInputBadge.stopLoading()
                            self.grammarIndicator.showStreamingResults(
                                response: parsed,
                                at: self.grammarRequestAnchor,
                                onSelect: { [weak self] selectedText in
                                    self?.applyGrammarSelection(selectedText)
                                },
                                onUserDismiss: { [weak self] in
                                    self?.cancelGrammarRequest(id: requestID)
                                    self?.finishFocusedInputWorkflow()
                                }
                            )
                        }
                    }
                }

                await MainActor.run {
                    guard self.grammarRequestID == requestID else { return }

                    let parsed = self.grammarAIService.parseResponse(from: response)
                    self.grammarHistoryStore.add(originalText: text, response: parsed)
                    self.grammarInputBadge.stopLoading()
                    if self.grammarResultsRequestID == requestID {
                        self.grammarIndicator.updateResults(response: parsed, isStreaming: false)
                    } else {
                        self.grammarIndicator.showResults(
                            response: parsed,
                            at: self.grammarRequestAnchor,
                            onSelect: { [weak self] selectedText in
                                self?.applyGrammarSelection(selectedText)
                            },
                            onUserDismiss: { [weak self] in
                                self?.finishFocusedInputWorkflow()
                            }
                        )
                    }
                    self.grammarRequestTask = nil
                    self.grammarRequestID = nil
                    self.grammarResultsRequestID = nil
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.grammarRequestID == requestID else { return }

                    self.grammarRequestTask = nil
                    self.grammarRequestID = nil
                    self.grammarInputBadge.stopLoading()
                    self.grammarIndicator.showError(at: self.grammarRequestAnchor)
                    self.finishFocusedInputWorkflow(after: 1.5)
                    self.logger.error("Grammar improvement failed: \(String(describing: error), privacy: .public)")
                    print("Grammar improvement failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func applyGrammarSelection(_ selectedText: String) {
        clipboardMonitor.writeToClipboard(text: selectedText)
        grammarSourceApp?.activate(options: [.activateAllWindows])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let input = self.grammarSourceInput {
                guard self.focusedTextInputService.focus(input) else {
                    self.finishGrammarReplacement(succeeded: false)
                    return
                }

                if let selection = self.grammarSourceSelection {
                    guard self.focusedTextInputService.restoreSelection(selection, in: input) else {
                        self.finishGrammarReplacement(succeeded: false)
                        return
                    }
                } else if !self.grammarHotkeyService.selectAllText() {
                    self.finishGrammarReplacement(succeeded: false)
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self.finishGrammarReplacement(
                        succeeded: self.grammarHotkeyService.pasteFromClipboard()
                    )
                }
            } else {
                self.finishGrammarReplacement(
                    succeeded: self.grammarHotkeyService.pasteFromClipboard()
                )
            }
        }
    }

    private func finishGrammarReplacement(succeeded: Bool) {
        if succeeded {
            if grammarSourceInput == nil {
                grammarIndicator.showSuccess(at: grammarRequestAnchor)
            } else {
                grammarIndicator.dismiss()
            }
        } else {
            grammarIndicator.showError(at: grammarRequestAnchor)
        }
        finishFocusedInputWorkflow(after: 0.6)
    }

    private func finishFocusedInputWorkflow(after delay: TimeInterval = 0) {
        grammarSourceInput = nil
        grammarSourceSelection = nil
        grammarRequestAnchor = nil
        focusedTextInputService.resume(after: delay)
    }

    private func cancelActiveGrammarRequest() {
        grammarRequestTask?.cancel()
        grammarRequestTask = nil
        grammarRequestID = nil
        grammarResultsRequestID = nil
    }

    private func cancelGrammarRequest(id: UUID) {
        guard grammarRequestID == id else { return }
        cancelActiveGrammarRequest()
    }

    /// Open settings window
    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(onDone: { [weak self] in
                self?.settingsWindow?.close()
            })
                .frame(minWidth: 720, minHeight: 620)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)

            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? "AuralAI"
            window.title = "\(appName) Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 820, height: 720))
            window.minSize = NSSize(width: 720, height: 620)
            window.center()
            window.isReleasedWhenClosed = false

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Quit application
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    /// Save speech history to CoreData
    private func saveSpeechHistory(text: String, source: String) {
        persistenceController.saveSpeechHistory(
            text: text,
            source: source,
            voice: settings.currentVoice.identifier,
            duration: 0.0
        )
    }

    private func observeSettings() {}

    func openSettingsFromMenuBar() {
        openSettings()
    }

    func quitFromMenuBar() {
        quitApp()
    }
}
#endif
