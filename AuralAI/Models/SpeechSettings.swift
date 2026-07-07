//
//  SpeechSettings.swift
//  AuralAI
//
//  Created by AuralAI Migration
//

import Foundation
import AVFoundation

/// Speech settings model with UserDefaults persistence
class SpeechSettings: ObservableObject {
    static let shared = SpeechSettings()

    enum LanguageOption: String, CaseIterable, Identifiable {
        case english = "en-US"
        case chinese = "zh-CN"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .english:
                return "English"
            case .chinese:
                return "Chinese"
            }
        }
    }

    struct HotkeyModifier: OptionSet {
        let rawValue: Int

        static let control = HotkeyModifier(rawValue: 1 << 0)
        static let option = HotkeyModifier(rawValue: 1 << 1)
        static let command = HotkeyModifier(rawValue: 1 << 2)
        static let shift = HotkeyModifier(rawValue: 1 << 3)

        static let `default`: HotkeyModifier = [.control]
    }

    private let defaults: UserDefaults

    // Keys for UserDefaults
    private enum Keys {
        static let voiceIdentifier = "voiceIdentifier"
        static let rate = "rate"
        static let pitch = "pitch"
        static let language = "language"
        static let hotkeyKey = "hotkeyKey"
        static let hotkeyModifiers = "hotkeyModifiers"
    }

    // MARK: - Published Properties

    @Published var voiceIdentifier: String? {
        didSet {
            defaults.set(voiceIdentifier, forKey: Keys.voiceIdentifier)
        }
    }

    @Published var rate: Float {
        didSet {
            defaults.set(rate, forKey: Keys.rate)
        }
    }

    @Published var pitch: Float {
        didSet {
            defaults.set(pitch, forKey: Keys.pitch)
        }
    }

    @Published var languageRawValue: String {
        didSet {
            let normalized = LanguageOption(rawValue: languageRawValue)?.rawValue ?? LanguageOption.english.rawValue
            if languageRawValue != normalized {
                languageRawValue = normalized
                return
            }

            defaults.set(languageRawValue, forKey: Keys.language)
        }
    }

    @Published var hotkeyKey: String {
        didSet {
            let normalized = SpeechSettings.normalizedHotkeyKey(from: hotkeyKey)
            if hotkeyKey != normalized {
                hotkeyKey = normalized
                return
            }
            defaults.set(hotkeyKey, forKey: Keys.hotkeyKey)
        }
    }

    @Published var hotkeyModifiersRawValue: Int {
        didSet {
            defaults.set(hotkeyModifiersRawValue, forKey: Keys.hotkeyModifiers)
        }
    }

    // MARK: - Initialization

    private init() {
        self.defaults = UserDefaults.standard
        Self.migrateLegacyDefaultsIfNeeded(using: defaults)

        // Load saved settings or use defaults
        self.voiceIdentifier = defaults.string(forKey: Keys.voiceIdentifier) ?? Self.defaultVoiceIdentifier
        self.rate = defaults.object(forKey: Keys.rate) as? Float ?? AVSpeechUtteranceDefaultSpeechRate
        self.pitch = defaults.object(forKey: Keys.pitch) as? Float ?? 1.0
        self.languageRawValue = LanguageOption(rawValue: defaults.string(forKey: Keys.language) ?? "")?.rawValue ?? LanguageOption.english.rawValue
        self.hotkeyKey = SpeechSettings.normalizedHotkeyKey(from: defaults.string(forKey: Keys.hotkeyKey) ?? "S")

        let storedModifiers = defaults.object(forKey: Keys.hotkeyModifiers) as? Int
        self.hotkeyModifiersRawValue = storedModifiers ?? HotkeyModifier.default.rawValue
    }

    /// Migrate settings from the old shared suite into the app-scoped defaults once.
    /// This keeps existing users' settings while allowing Debug/Release builds to diverge.
    private static func migrateLegacyDefaultsIfNeeded(using defaults: UserDefaults) {
        let legacySuiteIdentifier = "group.com.yourteam.speakit"
        let migrationFlagKey = "didMigrateFromLegacyAppGroupDefaults"

        guard !defaults.bool(forKey: migrationFlagKey) else { return }
        guard let legacyDefaults = UserDefaults(suiteName: legacySuiteIdentifier) else { return }

        let keys = [
            Keys.voiceIdentifier,
            Keys.rate,
            Keys.pitch,
            Keys.language,
            Keys.hotkeyKey,
            Keys.hotkeyModifiers
        ]

        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: migrationFlagKey)
    }

    // MARK: - Helper Methods

    /// Get the current voice or default system voice
    var currentVoice: AVSpeechSynthesisVoice {
        if let identifier = voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return SpeechSettings.preferredDefaultEnglishVoice()
            ?? AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice()
    }

    static var defaultVoiceIdentifier: String? {
        preferredDefaultEnglishVoice()?.identifier
    }

    /// Reset all settings to defaults
    func resetToDefaults() {
        voiceIdentifier = Self.defaultVoiceIdentifier
        rate = AVSpeechUtteranceDefaultSpeechRate
        pitch = 1.0
        language = .english
        hotkeyKey = "S"
        hotkeyModifiers = .default
    }

    /// Get all available voices grouped by language
    static func availableVoices() -> [String: [AVSpeechSynthesisVoice]] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return Dictionary(grouping: voices) { voice in
            voice.language
        }
    }

    /// Get all available voices as a flat array
    static func allVoices() -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
    }

    var language: LanguageOption {
        get { LanguageOption(rawValue: languageRawValue) ?? .english }
        set { languageRawValue = newValue.rawValue }
    }

    func englishVoices() -> [AVSpeechSynthesisVoice] {
        SpeechSettings.allVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .sorted(by: SpeechSettings.isPreferredVoice(_:over:))
    }

    var hotkeyModifiers: HotkeyModifier {
        get { HotkeyModifier(rawValue: hotkeyModifiersRawValue) }
        set { hotkeyModifiersRawValue = newValue.rawValue }
    }

    var hotkeyDisplayString: String {
        let modifierNames: [(HotkeyModifier, String)] = [
            (.control, "Ctrl"),
            (.option, "Option"),
            (.command, "Cmd"),
            (.shift, "Shift")
        ]

        let parts = modifierNames.compactMap { modifier, name in
            hotkeyModifiers.contains(modifier) ? name : nil
        }

        let key = hotkeyKey.isEmpty ? "?" : hotkeyKey.uppercased()
        return (parts + [key]).joined(separator: "+")
    }

    var supportsGlobalHotkey: Bool {
        SpeechSettings.keyCode(for: hotkeyKey) != nil && !hotkeyModifiers.isEmpty
    }

    func setModifier(_ modifier: HotkeyModifier, enabled: Bool) {
        var updated = hotkeyModifiers
        if enabled {
            updated.insert(modifier)
        } else {
            updated.remove(modifier)
        }
        hotkeyModifiers = updated
    }

    func isModifierEnabled(_ modifier: HotkeyModifier) -> Bool {
        hotkeyModifiers.contains(modifier)
    }

    static func keyCode(for key: String) -> UInt32? {
        keyCodeMap[normalizedHotkeyKey(from: key)]
    }

    static func supportedHotkeyKey(from key: String) -> String? {
        let normalized = normalizedHotkeyKey(from: key)
        return keyCodeMap[normalized] == nil ? nil : normalized
    }

    private static func normalizedHotkeyKey(from key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let first = trimmed.first else { return "S" }
        return String(first)
    }

    private static let keyCodeMap: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8,
        "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33,
        "I": 34, "P": 35, "L": 37, "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "N": 45, "M": 46, ".": 47
    ]

    static func preferredDefaultEnglishVoice() -> AVSpeechSynthesisVoice? {
        if let voice = preferredNamedDefaultVoice() {
            return voice
        }

        return englishVoicesSorted().first
    }

    private static func preferredNamedDefaultVoice() -> AVSpeechSynthesisVoice? {
        let preferredNames = ["samantha", "ava", "nicky", "allison", "susan", "daniel", "karen"]
        let voices = allVoices().filter { $0.language.lowercased().hasPrefix("en") }

        for name in preferredNames {
            if let voice = voices.first(where: {
                $0.language.lowercased() == "en-us" && $0.name.lowercased() == name
            }) {
                return voice
            }
        }

        for name in preferredNames {
            if let voice = voices.first(where: { $0.name.lowercased() == name }) {
                return voice
            }
        }

        return nil
    }

    private static func englishVoicesSorted() -> [AVSpeechSynthesisVoice] {
        allVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .sorted(by: isPreferredVoice(_:over:))
    }

    private static func isPreferredVoice(_ lhs: AVSpeechSynthesisVoice, over rhs: AVSpeechSynthesisVoice) -> Bool {
        let lhsScore = voicePreferenceScore(lhs)
        let rhsScore = voicePreferenceScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }

        if lhs.language != rhs.language {
            return lhs.language.localizedCaseInsensitiveCompare(rhs.language) == .orderedAscending
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func voicePreferenceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0

        switch voice.quality {
        case .premium:
            score += 300
        case .enhanced:
            score += 200
        default:
            break
        }

        let language = voice.language.lowercased()
        if language == "en-us" {
            score += 100
        } else if language.hasPrefix("en") {
            score += 50
        }

        let name = voice.name.lowercased()
        let normalVoiceNames = ["samantha", "ava", "nicky", "allison", "susan", "daniel", "karen"]
        if normalVoiceNames.contains(name) {
            score += 250
        }

        let noveltyVoiceNames = [
            "albert", "bad news", "bahh", "bells", "boing", "bubbles", "cellos", "wobble",
            "fred", "good news", "jester", "junior", "kathy", "organ", "superstar",
            "ralph", "trinoids", "whisper", "zarvox"
        ]
        if noveltyVoiceNames.contains(name) || voice.identifier.lowercased().contains("eloquence") {
            score -= 500
        }

        return score
    }
}

// MARK: - Codable Support for Serialization
extension SpeechSettings {
    struct CodableSettings: Codable, Equatable {
        let voiceIdentifier: String?
        let rate: Float
        let pitch: Float
        let language: String
        let hotkeyKey: String
        let hotkeyModifiers: Int
    }

    var codable: CodableSettings {
        CodableSettings(
            voiceIdentifier: voiceIdentifier,
            rate: rate,
            pitch: pitch,
            language: language.rawValue,
            hotkeyKey: hotkeyKey,
            hotkeyModifiers: hotkeyModifiers.rawValue
        )
    }

    func update(from codable: CodableSettings) {
        voiceIdentifier = codable.voiceIdentifier
        rate = codable.rate
        pitch = codable.pitch
        language = LanguageOption(rawValue: codable.language) ?? .english
        hotkeyKey = codable.hotkeyKey
        hotkeyModifiers = HotkeyModifier(rawValue: codable.hotkeyModifiers)
    }
}
