//
//  AuralAIApp.swift
//  AuralAI
//
//  Created by mac on 2026/3/21.
//

import SwiftUI

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
    private var settingsWindow: NSWindow?

    private let hotkeyService = GlobalHotkeyService.shared
    private let grammarHotkeyService = GrammarHotkeyService.shared
    private let clipboardMonitor = ClipboardMonitor.shared
    private let ttsService = TTSService.shared
    private let grammarAIService = GrammarAIService.shared
    private let grammarIndicator = GrammarFloatingIndicator.shared
    private let settings = SpeechSettings.shared
    private let grammarSettings = GrammarSettings.shared
    private let persistenceController = PersistenceController.shared
    private var grammarSourceApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 AuralAI applicationDidFinishLaunching")
        observeSettings()
        setupHotkeyHandler()
        setupGrammarHotkeyHandler()
        checkAccessibilityPermissions()

        DispatchQueue.main.async {
            self.openSettings()
        }

        print("✅ AuralAI started. Press \(settings.hotkeyDisplayString) to speak selected text.")
        print("✅ Grammar improvement available with \(grammarSettings.hotkeyDisplayString).")
    }

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

    /// Check and request accessibility permissions
    private func checkAccessibilityPermissions() {
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
        print("\(grammarSettings.hotkeyDisplayString) pressed - capturing selected text for grammar improvement")

        grammarIndicator.dismiss()
        grammarSourceApp = NSWorkspace.shared.frontmostApplication

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

    private func triggerGrammarImprovement(for text: String) {
        grammarIndicator.showLoading()

        Task {
            do {
                let response = try await self.grammarAIService.improveText(text)

                await MainActor.run {
                    let parsed = self.grammarAIService.parseResponse(from: response)
                    self.grammarIndicator.showResults(response: parsed) { [weak self] selectedText in
                        guard let self = self else { return }

                        self.clipboardMonitor.writeToClipboard(text: selectedText)
                        self.grammarSourceApp?.activate(options: [.activateAllWindows])

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if self.grammarHotkeyService.pasteFromClipboard() {
                                self.grammarIndicator.showSuccess()
                            } else {
                                self.grammarIndicator.showError()
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.grammarIndicator.showError()
                    print("Grammar improvement failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Open settings window
    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(onDone: { [weak self] in
                self?.settingsWindow?.close()
            })
                .frame(width: 620, height: 680)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)

            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "AuralAI Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 620, height: 680))
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
