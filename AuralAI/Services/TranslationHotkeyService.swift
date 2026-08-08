//
//  TranslationHotkeyService.swift
//  AuralAI
//

import AppKit
import Carbon
import Combine
import Foundation

final class TranslationHotkeyService {
    static let shared = TranslationHotkeyService()

    private static let hotKeySignature = OSType(0x54524149) // 'TRAI'
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

    func copySelectedText() -> Bool {
        guard AXIsProcessTrusted() else {
            print("Cannot copy selected text for translation: accessibility permissions not granted")
            return false
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        commandDown?.flags = .maskCommand
        let copyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        copyDown?.flags = .maskCommand
        let copyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        copyUp?.flags = .maskCommand
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        guard let commandDown, let copyDown, let copyUp, let commandUp else { return false }
        let tap = CGEventTapLocation.cghidEventTap
        commandDown.post(tap: tap)
        copyDown.post(tap: tap)
        copyUp.post(tap: tap)
        commandUp.post(tap: tap)
        return true
    }

    private func observeSettings() {
        let settings = TranslationSettings.shared
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
            startAccessibilityRetry()
            return
        }
        stopAccessibilityRetry()

        let settings = TranslationSettings.shared
        guard let keyCode = GrammarSettings.keyCode(for: settings.hotkeyKey) else { return }
        let modifiers = settings.carbonModifiers()
        guard modifiers != 0 else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        if eventHandler == nil {
            let status = InstallEventHandler(
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
                          hotKeyID.signature == TranslationHotkeyService.hotKeySignature,
                          hotKeyID.id == TranslationHotkeyService.hotKeyID else {
                        return OSStatus(eventNotHandledErr)
                    }
                    let service = Unmanaged<TranslationHotkeyService>
                        .fromOpaque(userData)
                        .takeUnretainedValue()
                    service.handleHotkeyPress()
                    return noErr
                },
                1,
                &eventSpec,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            guard status == noErr else {
                eventHandler = nil
                print("Failed to install translation hotkey event handler: \(status)")
                return
            }
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, hotKeyRef != nil else {
            hotKeyRef = nil
            print("Failed to register translation hotkey: \(status)")
            return
        }
        print("Translation hotkey registered: \(settings.hotkeyDisplayString)")
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func handleHotkeyPress() {
        DispatchQueue.main.async {
            self.onHotkeyTriggered?()
        }
    }

    private func startAccessibilityRetry() {
        guard accessibilityRetryTimer == nil else { return }
        DispatchQueue.main.async {
            guard self.accessibilityRetryTimer == nil else { return }
            self.accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, AXIsProcessTrusted() else { return }
                self.refreshRegistration()
            }
        }
    }

    private func stopAccessibilityRetry() {
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = nil
    }
}
