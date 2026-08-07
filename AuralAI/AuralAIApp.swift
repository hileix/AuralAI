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
    private var selectionMouseMonitor: Any?
    private var applicationActivationObserver: NSObjectProtocol?
    private var clipboardSelectionBadgeVisible = false
    private var selectionProbeSuppressedUntil = Date.distantPast
    private var selectionBadgeSuppressedAfterAppSwitch = false
    private var mouseSelectionActive = false
    private var badgeMouseClickActive = false
    private var selectionBadgeAnchor: NSPoint?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 AuralAI applicationDidFinishLaunching")
        observeSettings()
        setupHotkeyHandler()
        setupGrammarHotkeyHandler()
        setupFocusedTextInputHandler()
        setupSelectionMouseMonitor()
        setupApplicationSwitchMonitor()
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

    func applicationWillTerminate(_ notification: Notification) {
        if let selectionMouseMonitor {
            NSEvent.removeMonitor(selectionMouseMonitor)
        }
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        openSettings()
        return false
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
            guard !self.grammarInputBadge.isLoading else { return }
            guard !self.selectionBadgeSuppressedAfterAppSwitch else {
                self.grammarInputBadge.hide()
                return
            }

            self.clipboardSelectionBadgeVisible = false

            if self.mouseSelectionActive {
                self.grammarInputBadge.hide()
                return
            }

            guard let input else {
                self.grammarInputBadge.hide()
                return
            }

            guard input.hasContent else {
                self.grammarInputBadge.hide()
                return
            }

            let onClick: () -> Void = { [weak self] in
                self?.handleFocusedTextInput(input)
            }
            if input.hasSelection {
                self.grammarInputBadge.show(
                    at: self.selectionBadgeAnchor ?? NSEvent.mouseLocation,
                    onClick: onClick
                )
            } else {
                self.selectionBadgeAnchor = nil
                self.grammarInputBadge.show(for: input.frame, onClick: onClick)
            }
        }

        focusedTextInputService.onExternalSelectionChange = { [weak self] selection in
            guard let self else { return }
            guard !self.grammarInputBadge.isLoading else { return }
            guard !self.selectionBadgeSuppressedAfterAppSwitch else {
                self.grammarInputBadge.hide()
                return
            }

            self.clipboardSelectionBadgeVisible = false

            if self.mouseSelectionActive {
                self.grammarInputBadge.hide()
                return
            }

            guard selection != nil else {
                self.selectionBadgeAnchor = nil
                if self.focusedTextInputService.currentInput == nil {
                    self.grammarInputBadge.hide()
                }
                return
            }

            self.grammarInputBadge.show(at: self.selectionBadgeAnchor ?? NSEvent.mouseLocation) { [weak self] in
                guard let self else { return }
                self.selectionProbeSuppressedUntil = Date().addingTimeInterval(1)
                self.handleGrammarGlobalHotkey()
            }
        }
    }

    private func setupSelectionMouseMonitor() {
        selectionMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let mouseLocation = NSEvent.mouseLocation
            DispatchQueue.main.async {
                guard let self else { return }
                if event.type == .leftMouseDown {
                    self.badgeMouseClickActive = self.grammarInputBadge.contains(mouseLocation)
                    guard !self.badgeMouseClickActive else { return }
                    self.beginMouseSelection()
                } else {
                    if self.badgeMouseClickActive {
                        self.badgeMouseClickActive = false
                        return
                    }
                    self.finishMouseSelection(at: mouseLocation)
                }
            }
        }
    }

    private func setupApplicationSwitchMonitor() {
        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.selectionBadgeSuppressedAfterAppSwitch = true
            self.selectionBadgeAnchor = nil
            self.clipboardSelectionBadgeVisible = false
            self.mouseSelectionActive = false
            self.badgeMouseClickActive = false
            self.grammarInputBadge.hide()
        }
    }

    private func beginMouseSelection() {
        mouseSelectionActive = true
        selectionBadgeAnchor = nil
        clipboardSelectionBadgeVisible = false
        grammarInputBadge.hide()
    }

    private func finishMouseSelection(at mouseLocation: NSPoint) {
        mouseSelectionActive = false
        selectionBadgeSuppressedAfterAppSwitch = false
        selectionBadgeAnchor = mouseLocation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.presentSelectionBadge(at: mouseLocation)
        }
    }

    private func presentSelectionBadge(at mouseLocation: NSPoint) {
        guard !selectionBadgeSuppressedAfterAppSwitch,
              Date() >= selectionProbeSuppressedUntil,
              let sourceApp = NSWorkspace.shared.frontmostApplication,
              sourceApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        let input = focusedTextInputService.captureCurrentInput()
        if let input, input.hasSelection {
            grammarInputBadge.show(at: mouseLocation) { [weak self] in
                self?.handleFocusedTextInput(input)
            }
            return
        }

        if focusedTextInputService.hasExternalSelection {
            grammarInputBadge.show(at: mouseLocation) { [weak self] in
                guard let self else { return }
                self.selectionProbeSuppressedUntil = Date().addingTimeInterval(1)
                self.handleGrammarGlobalHotkey()
            }
            return
        }

        if let input, input.hasContent, !isTerminalApplication(sourceApp) {
            grammarInputBadge.show(for: input.frame) { [weak self] in
                self?.handleFocusedTextInput(input)
            }
            return
        }

        if isTerminalApplication(sourceApp) {
            detectTerminalSelection(at: mouseLocation)
        } else {
            grammarInputBadge.hide()
        }
    }

    private func detectTerminalSelection(at mouseLocation: NSPoint) {
        guard !selectionBadgeSuppressedAfterAppSwitch,
              Date() >= selectionProbeSuppressedUntil,
              let sourceApp = NSWorkspace.shared.frontmostApplication,
              isTerminalApplication(sourceApp),
              focusedTextInputService.currentInput?.hasSelection != true,
              !focusedTextInputService.hasExternalSelection else {
            return
        }

        let pasteboardContents = clipboardMonitor.snapshotContents()
        let previousChangeCount = clipboardMonitor.currentChangeCount()
        logger.notice("Checking terminal selection app=\(sourceApp.localizedName ?? "unknown", privacy: .public)")
        guard grammarHotkeyService.copySelectedText() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }

            let clipboardChanged = self.clipboardMonitor.currentChangeCount() != previousChangeCount
            let selectedText = clipboardChanged ? self.clipboardMonitor.readClipboardText() : nil
            self.logger.notice(
                "Terminal selection check changed=\(clipboardChanged) length=\(selectedText?.count ?? 0)"
            )
            if clipboardChanged {
                self.clipboardMonitor.restoreContents(pasteboardContents)
            }

            guard let selectedText,
                  FocusedTextInputService.hasMeaningfulContent(selectedText) else {
                self.selectionBadgeAnchor = nil
                self.clipboardSelectionBadgeVisible = false
                if let input = self.focusedTextInputService.currentInput,
                   input.hasContent {
                    self.grammarInputBadge.show(for: input.frame) { [weak self] in
                        self?.handleFocusedTextInput(input)
                    }
                } else {
                    self.grammarInputBadge.hide()
                }
                return
            }

            self.clipboardSelectionBadgeVisible = true
            self.grammarInputBadge.show(at: mouseLocation) { [weak self] in
                guard let self else { return }
                self.selectionProbeSuppressedUntil = Date().addingTimeInterval(1)
                self.clipboardSelectionBadgeVisible = false
                self.handleGrammarGlobalHotkey()
            }
        }
    }

    private func isTerminalApplication(_ application: NSRunningApplication) -> Bool {
        let bundleIdentifier = application.bundleIdentifier?.lowercased() ?? ""
        let name = application.localizedName?.lowercased() ?? ""
        let terminalIdentifiers = [
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "dev.warp.warp-stable",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.github.wez.wezterm"
        ]
        let terminalNames = ["terminal", "iterm", "ghostty", "warp", "kitty", "alacritty", "wezterm"]
        return terminalIdentifiers.contains(bundleIdentifier)
            || terminalNames.contains(where: { name.contains($0) })
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

        if grammarInputBadge.centerPoint == nil {
            grammarInputBadge.show(at: selectionBadgeAnchor ?? NSEvent.mouseLocation) { [weak self] in
                self?.handleGrammarGlobalHotkey()
            }
        }
        let badgeAnchor = grammarInputBadge.centerPoint
            ?? selectionBadgeAnchor
            ?? NSEvent.mouseLocation
        grammarRequestAnchor = badgeAnchor
        grammarInputBadge.showLoading()

        let previousChangeCount = clipboardMonitor.currentChangeCount()
        guard grammarHotkeyService.copySelectedText() else {
            grammarInputBadge.stopLoading()
            grammarIndicator.showError(at: badgeAnchor)
            finishFocusedInputWorkflow(after: 1.5)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard self.clipboardMonitor.currentChangeCount() != previousChangeCount else {
                print("Clipboard did not change after grammar copy command")
                self.grammarInputBadge.stopLoading()
                self.grammarIndicator.showError(at: badgeAnchor)
                self.finishFocusedInputWorkflow(after: 1.5)
                return
            }

            guard let text = self.clipboardMonitor.readClipboardText(),
                  FocusedTextInputService.hasMeaningfulContent(text) else {
                print("No text found in clipboard for grammar improvement")
                self.grammarInputBadge.stopLoading()
                self.grammarIndicator.showError(at: badgeAnchor)
                self.finishFocusedInputWorkflow(after: 1.5)
                return
            }

            print("✅ Text captured for grammar improvement: \(text.prefix(50))...")
            self.triggerGrammarImprovement(for: text, anchor: badgeAnchor, showLoadingIndicator: false)
        }
    }

    private func handleFocusedTextInput(_ input: FocusedTextInput) {
        selectionProbeSuppressedUntil = Date().addingTimeInterval(1)
        cancelActiveGrammarRequest()
        grammarIndicator.dismiss()

        if grammarInputBadge.centerPoint == nil {
            grammarInputBadge.show(for: input.frame) { [weak self] in
                self?.handleFocusedTextInput(input)
            }
        }
        let badgeAnchor = grammarInputBadge.centerPoint ?? input.anchorPoint
        let sourceSelection = focusedTextInputService.readSelection(from: input)
            ?? input.selectedText.map {
                FocusedTextSelection(text: $0, range: input.selectedRange)
            }
        grammarSourceInput = input
        grammarSourceSelection = sourceSelection
        grammarSourceApp = NSRunningApplication(processIdentifier: input.processIdentifier)
        grammarRequestAnchor = badgeAnchor
        focusedTextInputService.pause()

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
        grammarRequestAnchor = anchor

        if let cachedResponse = grammarHistoryStore.response(matching: text) {
            logger.notice("Using cached grammar response length=\(text.count)")
            grammarIndicator.showResults(
                response: cachedResponse,
                at: grammarRequestAnchor,
                onSelect: { [weak self] selectedText in
                    self?.applyGrammarSelection(selectedText)
                },
                onUserDismiss: { [weak self] in
                    self?.finishFocusedInputWorkflow()
                },
                onPresented: { [weak self] in
                    self?.grammarInputBadge.stopLoading()
                }
            )
            return
        }

        let requestID = UUID()
        grammarRequestID = requestID
        if showLoadingIndicator {
            if let anchor {
                grammarIndicator.showLoading(at: anchor)
            } else {
                grammarIndicator.showLoading()
            }
        } else {
            grammarInputBadge.showLoading()
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
                            self.grammarIndicator.showStreamingResults(
                                response: parsed,
                                at: self.grammarRequestAnchor,
                                onSelect: { [weak self] selectedText in
                                    self?.applyGrammarSelection(selectedText)
                                },
                                onUserDismiss: { [weak self] in
                                    self?.cancelGrammarRequest(id: requestID)
                                    self?.finishFocusedInputWorkflow()
                                },
                                onPresented: { [weak self] in
                                    self?.grammarInputBadge.stopLoading()
                                }
                            )
                        }
                    }
                }

                await MainActor.run {
                    guard self.grammarRequestID == requestID else { return }

                    let parsed = self.grammarAIService.parseResponse(from: response)
                    self.grammarHistoryStore.add(originalText: text, response: parsed)
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
                            },
                            onPresented: { [weak self] in
                                self?.grammarInputBadge.stopLoading()
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
            grammarIndicator.dismiss()
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
