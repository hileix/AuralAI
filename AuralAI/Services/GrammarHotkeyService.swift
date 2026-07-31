//
//  GrammarHotkeyService.swift
//  AuralAI
//

import Foundation
import AppKit
import Carbon
import Combine

final class GrammarHotkeyService {
    static let shared = GrammarHotkeyService()

    private static let hotKeySignature = OSType(0x47524149) // 'GRAI'
    private static let hotKeyID = UInt32(1)

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityRetryTimer: Timer?

    var onHotkeyTriggered: (() -> Void)?

    private init() {
        observeSettings()
        setupGlobalHotkey()
    }

    deinit {
        unregisterHotkey()
    }

    func refreshRegistration() {
        unregisterHotkey()
        setupGlobalHotkey()
    }

    func hasAccessibilityPermissions() -> Bool {
        AXIsProcessTrusted()
    }

    func copySelectedText() -> Bool {
        postCommandKey(virtualKey: 0x08, label: "Cmd+C")
    }

    func pasteFromClipboard() -> Bool {
        postCommandKey(virtualKey: 0x09, label: "Cmd+V")
    }

    func selectAllText() -> Bool {
        postCommandKey(virtualKey: 0x00, label: "Cmd+A")
    }

    private func observeSettings() {
        let settings = GrammarSettings.shared

        settings.$hotkeyKey
            .dropFirst()
            .sink { [weak self] _ in self?.refreshRegistration() }
            .store(in: &cancellables)

        settings.$hotkeyModifiersRawValue
            .dropFirst()
            .sink { [weak self] _ in self?.refreshRegistration() }
            .store(in: &cancellables)
    }

    private func setupGlobalHotkey() {
        guard AXIsProcessTrusted() else {
            print("Accessibility permissions not granted. Cannot register grammar hotkey.")
            startAccessibilityRetry()
            return
        }
        stopAccessibilityRetry()

        let settings = GrammarSettings.shared

        guard let keyCode = GrammarSettings.keyCode(for: settings.hotkeyKey) else {
            print("Invalid grammar hotkey key: \(settings.hotkeyKey)")
            return
        }

        let modifiers = settings.carbonModifiers()
        guard modifiers != 0 else {
            print("Grammar hotkey modifiers must not be empty.")
            return
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        if eventHandler == nil {
            let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, userData) -> OSStatus in
                    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

                    var hotKeyID = EventHotKeyID()
                    let status = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )

                    guard status == noErr,
                          hotKeyID.signature == GrammarHotkeyService.hotKeySignature,
                          hotKeyID.id == GrammarHotkeyService.hotKeyID else {
                        return OSStatus(eventNotHandledErr)
                    }

                    let service = Unmanaged<GrammarHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                    service.handleHotkeyPress()
                    return noErr
                },
                1,
                &eventSpec,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )

            guard handlerStatus == noErr else {
                eventHandler = nil
                print("Failed to install grammar hotkey event handler: \(handlerStatus)")
                return
            }
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let registrationStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        guard registrationStatus == noErr, hotKeyRef != nil else {
            hotKeyRef = nil
            print("Failed to register grammar hotkey: \(registrationStatus)")
            return
        }

        print("Grammar hotkey registered: \(settings.hotkeyDisplayString)")
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func handleHotkeyPress() {
        print("Grammar hotkey triggered: \(GrammarSettings.shared.hotkeyDisplayString)")
        DispatchQueue.main.async {
            self.onHotkeyTriggered?()
        }
    }

    private func postCommandKey(virtualKey: CGKeyCode, label: String) -> Bool {
        guard hasAccessibilityPermissions() else {
            print("Cannot post \(label): accessibility permissions not granted")
            return false
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        keyUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        guard let cmdDown, let keyDown, let keyUp, let cmdUp else {
            print("Failed to create keyboard events for \(label)")
            return false
        }

        let tap = CGEventTapLocation.cghidEventTap
        cmdDown.post(tap: tap)
        keyDown.post(tap: tap)
        keyUp.post(tap: tap)
        cmdUp.post(tap: tap)
        return true
    }

    private func startAccessibilityRetry() {
        guard accessibilityRetryTimer == nil else { return }

        DispatchQueue.main.async {
            guard self.accessibilityRetryTimer == nil else { return }

            self.accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.hasAccessibilityPermissions() {
                    self.refreshRegistration()
                }
            }
        }
    }

    private func stopAccessibilityRetry() {
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = nil
    }
}
