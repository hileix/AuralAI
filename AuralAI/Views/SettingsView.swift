//
//  SettingsView.swift
//  AuralAI
//
//  Created by AuralAI Migration
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    private enum UILanguage {
        case english
        case chinese
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = SpeechSettings.shared
    @StateObject private var grammarSettings = GrammarSettings.shared
    @StateObject private var ttsService = TTSService.shared

    @State private var testText = "This is a test of the speech settings."
    @State private var draftVoiceIdentifier: String?
    @State private var draftRate: Float
    @State private var draftPitch: Float
    @State private var draftLanguageRawValue: String
    @State private var draftHotkeyKey: String
    @State private var draftHotkeyModifiersRawValue: Int
    @State private var hotkeyInput: String
    @State private var initialSettingsSnapshot: SpeechSettings.CodableSettings
    @State private var lastPreviewedVoiceIdentifier: String?
    @State private var draftGrammarPrompt: String
    @State private var draftGrammarModel: String
    @State private var draftGrammarBaseURL: String
    @State private var draftGrammarAPIKey: String
    @State private var draftGrammarAPIModeRawValue: String
    @State private var draftGrammarMaxTokens: Int
    @State private var draftGrammarHotkeyKey: String
    @State private var draftGrammarHotkeyModifiersRawValue: Int
    @State private var grammarHotkeyInput: String
    @State private var initialGrammarSettingsSnapshot: GrammarSettings.CodableSettings
    @State private var validationMessage: String?

    let onDone: (() -> Void)?

    init(onDone: (() -> Void)? = nil) {
        self.onDone = onDone
        let currentSettings = SpeechSettings.shared.codable
        let currentGrammarSettings = GrammarSettings.shared.codable
        _draftVoiceIdentifier = State(initialValue: currentSettings.voiceIdentifier)
        _draftRate = State(initialValue: currentSettings.rate)
        _draftPitch = State(initialValue: currentSettings.pitch)
        _draftLanguageRawValue = State(initialValue: currentSettings.language)
        _draftHotkeyKey = State(initialValue: currentSettings.hotkeyKey)
        _draftHotkeyModifiersRawValue = State(initialValue: currentSettings.hotkeyModifiers)
        _hotkeyInput = State(initialValue: currentSettings.hotkeyKey)
        _initialSettingsSnapshot = State(initialValue: currentSettings)
        _lastPreviewedVoiceIdentifier = State(initialValue: currentSettings.voiceIdentifier)
        _draftGrammarPrompt = State(initialValue: currentGrammarSettings.systemPrompt)
        _draftGrammarModel = State(initialValue: currentGrammarSettings.modelName)
        _draftGrammarBaseURL = State(initialValue: currentGrammarSettings.baseURL)
        _draftGrammarAPIKey = State(initialValue: currentGrammarSettings.apiKey)
        _draftGrammarAPIModeRawValue = State(initialValue: currentGrammarSettings.apiMode)
        _draftGrammarMaxTokens = State(initialValue: currentGrammarSettings.maxTokens)
        _draftGrammarHotkeyKey = State(initialValue: currentGrammarSettings.hotkeyKey)
        _draftGrammarHotkeyModifiersRawValue = State(initialValue: currentGrammarSettings.hotkeyModifiers)
        _grammarHotkeyInput = State(initialValue: currentGrammarSettings.hotkeyKey)
        _initialGrammarSettingsSnapshot = State(initialValue: currentGrammarSettings)
    }

    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        NavigationView {
            settingsForm
                .navigationTitle(copy.settingsTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(copy.saveButton) {
                            saveChanges()
                        }
                        .disabled(!hasChanges)
                    }
                }
        }
        #endif
    }

    private func testSpeech() {
        ttsService.speak(
            text: testText,
            voiceIdentifier: draftVoiceIdentifier,
            fallbackVoice: previewVoice,
            rate: draftRate,
            pitch: draftPitch
        )
    }

    private func saveChanges() {
        guard !hasDuplicateHotkeys else {
            validationMessage = copy.duplicateShortcutMessage
            return
        }

        settings.update(from: draftSettings)
        grammarSettings.update(from: draftGrammarSettings)
        initialSettingsSnapshot = draftSettings
        initialGrammarSettingsSnapshot = draftGrammarSettings
        validationMessage = nil
    }

    private func closeView() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    private var draftSettings: SpeechSettings.CodableSettings {
        SpeechSettings.CodableSettings(
            voiceIdentifier: draftVoiceIdentifier,
            rate: draftRate,
            pitch: draftPitch,
            language: draftLanguageRawValue,
            hotkeyKey: draftHotkeyKey,
            hotkeyModifiers: draftHotkeyModifiersRawValue
        )
    }

    private var draftGrammarSettings: GrammarSettings.CodableSettings {
        GrammarSettings.CodableSettings(
            systemPrompt: draftGrammarPrompt,
            maxTokens: draftGrammarMaxTokens,
            modelName: draftGrammarModel,
            baseURL: draftGrammarBaseURL,
            apiKey: draftGrammarAPIKey,
            apiMode: draftGrammarAPIModeRawValue,
            hotkeyKey: draftGrammarHotkeyKey,
            hotkeyModifiers: draftGrammarHotkeyModifiersRawValue
        )
    }

    private var hasChanges: Bool {
        draftSettings != initialSettingsSnapshot || draftGrammarSettings != initialGrammarSettingsSnapshot
    }

    private var hasDuplicateHotkeys: Bool {
        draftHotkeyKey.caseInsensitiveCompare(draftGrammarHotkeyKey) == .orderedSame
            && draftHotkeyModifiersRawValue == draftGrammarHotkeyModifiersRawValue
    }

    private var previewVoice: AVSpeechSynthesisVoice {
        if let identifier = draftVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return SpeechSettings.preferredDefaultEnglishVoice()
            ?? AVSpeechSynthesisVoice(language: "en-US")
            ?? AVSpeechSynthesisVoice()
    }

    private var draftHotkeyDisplayString: String {
        let modifiers = SpeechSettings.HotkeyModifier(rawValue: draftHotkeyModifiersRawValue)
        let modifierNames: [(SpeechSettings.HotkeyModifier, String)] = [
            (.control, "Ctrl"),
            (.option, "Option"),
            (.command, "Cmd"),
            (.shift, "Shift")
        ]

        let parts = modifierNames.compactMap { modifier, name in
            modifiers.contains(modifier) ? name : nil
        }

        let key = draftHotkeyKey.isEmpty ? "?" : draftHotkeyKey.uppercased()
        return (parts + [key]).joined(separator: "+")
    }

    private var modifierOptions: [(label: String, value: Int)] {
        [
            (copy.controlLabel, SpeechSettings.HotkeyModifier.control.rawValue),
            (copy.optionLabel, SpeechSettings.HotkeyModifier.option.rawValue),
            (copy.commandLabel, SpeechSettings.HotkeyModifier.command.rawValue),
            (copy.shiftLabel, SpeechSettings.HotkeyModifier.shift.rawValue),
            ("\(copy.controlLabel) + \(copy.optionLabel)", SpeechSettings.HotkeyModifier([.control, .option]).rawValue),
            ("\(copy.controlLabel) + \(copy.commandLabel)", SpeechSettings.HotkeyModifier([.control, .command]).rawValue),
            ("\(copy.controlLabel) + \(copy.shiftLabel)", SpeechSettings.HotkeyModifier([.control, .shift]).rawValue),
            ("\(copy.optionLabel) + \(copy.commandLabel)", SpeechSettings.HotkeyModifier([.option, .command]).rawValue),
            ("\(copy.optionLabel) + \(copy.shiftLabel)", SpeechSettings.HotkeyModifier([.option, .shift]).rawValue),
            ("\(copy.commandLabel) + \(copy.shiftLabel)", SpeechSettings.HotkeyModifier([.command, .shift]).rawValue),
            ("\(copy.controlLabel) + \(copy.optionLabel) + \(copy.commandLabel)", SpeechSettings.HotkeyModifier([.control, .option, .command]).rawValue),
            ("\(copy.controlLabel) + \(copy.optionLabel) + \(copy.shiftLabel)", SpeechSettings.HotkeyModifier([.control, .option, .shift]).rawValue),
            ("\(copy.controlLabel) + \(copy.commandLabel) + \(copy.shiftLabel)", SpeechSettings.HotkeyModifier([.control, .command, .shift]).rawValue),
            ("\(copy.optionLabel) + \(copy.commandLabel) + \(copy.shiftLabel)", SpeechSettings.HotkeyModifier([.option, .command, .shift]).rawValue),
            ("\(copy.controlLabel) + \(copy.optionLabel) + \(copy.commandLabel) + \(copy.shiftLabel)", SpeechSettings.HotkeyModifier([.control, .option, .command, .shift]).rawValue)
        ]
    }

    private var grammarModifierOptions: [(label: String, value: Int)] {
        [
            (copy.controlLabel, GrammarSettings.HotkeyModifier.control.rawValue),
            (copy.optionLabel, GrammarSettings.HotkeyModifier.option.rawValue),
            (copy.commandLabel, GrammarSettings.HotkeyModifier.command.rawValue),
            (copy.shiftLabel, GrammarSettings.HotkeyModifier.shift.rawValue),
            ("\(copy.controlLabel) + \(copy.optionLabel)", GrammarSettings.HotkeyModifier([.control, .option]).rawValue),
            ("\(copy.controlLabel) + \(copy.commandLabel)", GrammarSettings.HotkeyModifier([.control, .command]).rawValue),
            ("\(copy.controlLabel) + \(copy.shiftLabel)", GrammarSettings.HotkeyModifier([.control, .shift]).rawValue),
            ("\(copy.optionLabel) + \(copy.commandLabel)", GrammarSettings.HotkeyModifier([.option, .command]).rawValue),
            ("\(copy.optionLabel) + \(copy.shiftLabel)", GrammarSettings.HotkeyModifier([.option, .shift]).rawValue),
            ("\(copy.commandLabel) + \(copy.shiftLabel)", GrammarSettings.HotkeyModifier([.command, .shift]).rawValue),
            ("\(copy.controlLabel) + \(copy.optionLabel) + \(copy.commandLabel)", GrammarSettings.HotkeyModifier([.control, .option, .command]).rawValue),
            ("\(copy.controlLabel) + \(copy.optionLabel) + \(copy.shiftLabel)", GrammarSettings.HotkeyModifier([.control, .option, .shift]).rawValue),
            ("\(copy.controlLabel) + \(copy.commandLabel) + \(copy.shiftLabel)", GrammarSettings.HotkeyModifier([.control, .command, .shift]).rawValue),
            ("\(copy.optionLabel) + \(copy.commandLabel) + \(copy.shiftLabel)", GrammarSettings.HotkeyModifier([.option, .command, .shift]).rawValue),
            ("\(copy.controlLabel) + \(copy.optionLabel) + \(copy.commandLabel) + \(copy.shiftLabel)", GrammarSettings.HotkeyModifier([.control, .option, .command, .shift]).rawValue)
        ]
    }

    private var draftGrammarHotkeyDisplayString: String {
        GrammarSettings.displayString(
            key: draftGrammarHotkeyKey,
            modifiers: GrammarSettings.HotkeyModifier(rawValue: draftGrammarHotkeyModifiersRawValue)
        )
    }

    private var settingsForm: some View {
        Form {
            Section(copy.shortcutSection) {
                TextField(copy.shortcutKeyLabel, text: $hotkeyInput)
                    .onChange(of: hotkeyInput) { _, newValue in
                        let normalized = SpeechSettings.supportedHotkeyKey(from: newValue) ?? "S"
                        hotkeyInput = normalized
                        draftHotkeyKey = normalized
                    }

                Picker(copy.modifierLabel, selection: $draftHotkeyModifiersRawValue) {
                    ForEach(modifierOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                HStack {
                    Text(copy.currentShortcutLabel)
                    Spacer()
                    Text(draftHotkeyDisplayString)
                        .foregroundColor(.secondary)
                }

                Text(copy.shortcutHelp)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(copy.languageSection) {
                Picker(copy.languageLabel, selection: $draftLanguageRawValue) {
                    ForEach(SpeechSettings.LanguageOption.allCases) { language in
                        Text(localizedTitle(for: language)).tag(language.rawValue)
                    }
                }

                Text(copy.languageHelp)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(copy.voiceSection) {

                Picker(copy.voiceLabel, selection: $draftVoiceIdentifier) {
                    Text(copy.defaultVoiceLabel).tag(nil as String?)
                    ForEach(settings.englishVoices(), id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice.identifier as String?)
                    }
                }
                .onChange(of: draftVoiceIdentifier) { _, newValue in
                    previewVoiceIfNeeded(newValue)
                }

                Text(copy.voiceHelp)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(copy.rateSection) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(copy.rateLabel)
                        Spacer()
                        Text(String(format: "%.2f", draftRate))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $draftRate, in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                    Text(copy.rateHelp)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section(copy.pitchSection) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(copy.pitchLabel)
                        Spacer()
                        Text(String(format: "%.2f", draftPitch))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $draftPitch, in: 0.5...2.0)
                    Text(copy.pitchHelp)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(action: testSpeech) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                        Text(copy.testSpeechButton)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button(action: {
                    let defaultSettings = SpeechSettings.CodableSettings(
                        voiceIdentifier: SpeechSettings.defaultVoiceIdentifier,
                        rate: AVSpeechUtteranceDefaultSpeechRate,
                        pitch: 1.0,
                        language: SpeechSettings.LanguageOption.english.rawValue,
                        hotkeyKey: "S",
                        hotkeyModifiers: SpeechSettings.HotkeyModifier.default.rawValue
                    )
                    draftVoiceIdentifier = defaultSettings.voiceIdentifier
                    draftRate = defaultSettings.rate
                    draftPitch = defaultSettings.pitch
                    draftLanguageRawValue = defaultSettings.language
                    draftHotkeyKey = defaultSettings.hotkeyKey
                    draftHotkeyModifiersRawValue = defaultSettings.hotkeyModifiers
                    hotkeyInput = defaultSettings.hotkeyKey
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(copy.resetDefaultsButton)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var grammarSettingsForm: some View {
        Form {
            Section(copy.grammarShortcutSection) {
                TextField(copy.shortcutKeyLabel, text: $grammarHotkeyInput)
                    .onChange(of: grammarHotkeyInput) { _, newValue in
                        let normalized = GrammarSettings.supportedHotkeyKey(from: newValue) ?? GrammarSettings.defaultHotkeyKey
                        grammarHotkeyInput = normalized
                        draftGrammarHotkeyKey = normalized
                    }

                Picker(copy.modifierLabel, selection: $draftGrammarHotkeyModifiersRawValue) {
                    ForEach(grammarModifierOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }

                HStack {
                    Text(copy.currentShortcutLabel)
                    Spacer()
                    Text(draftGrammarHotkeyDisplayString)
                        .foregroundColor(hasDuplicateHotkeys ? .red : .secondary)
                }

                if hasDuplicateHotkeys {
                    Text(copy.duplicateShortcutMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }

            Section(copy.modelSection) {
                Picker(copy.apiModeLabel, selection: $draftGrammarAPIModeRawValue) {
                    ForEach(GrammarSettings.APIMode.allCases) { mode in
                        Text(localizedTitle(for: mode)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                TextField(copy.modelLabel, text: $draftGrammarModel)
                TextField(copy.baseURLLabel, text: $draftGrammarBaseURL)
                SecureField(copy.apiKeyLabel, text: $draftGrammarAPIKey)

                HStack {
                    Text(copy.maxTokensLabel)
                    Spacer()
                    TextField("1024", value: $draftGrammarMaxTokens, format: .number)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section(copy.systemPromptSection) {
                TextEditor(text: $draftGrammarPrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
            }

            Section {
                Button(action: {
                    let defaultSettings = GrammarSettings.CodableSettings.defaults
                    draftGrammarPrompt = defaultSettings.systemPrompt
                    draftGrammarModel = defaultSettings.modelName
                    draftGrammarBaseURL = defaultSettings.baseURL
                    draftGrammarAPIKey = defaultSettings.apiKey
                    draftGrammarAPIModeRawValue = defaultSettings.apiMode
                    draftGrammarMaxTokens = defaultSettings.maxTokens
                    draftGrammarHotkeyKey = defaultSettings.hotkeyKey
                    draftGrammarHotkeyModifiersRawValue = defaultSettings.hotkeyModifiers
                    grammarHotkeyInput = defaultSettings.hotkeyKey
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(copy.resetGrammarDefaultsButton)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    #if os(macOS)
    private var macOSContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text(copy.settingsTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(copy.saveButton) {
                    saveChanges()
                }
                .disabled(!hasChanges)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            TabView {
                settingsForm
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .tabItem {
                        Text(copy.speechTab)
                    }

                grammarSettingsForm
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .tabItem {
                        Text(copy.grammarTab)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(copy.settingsTitle, isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button(copy.okButton, role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }
    #endif

    private var uiLanguage: UILanguage {
        draftLanguageRawValue == SpeechSettings.LanguageOption.chinese.rawValue ? .chinese : .english
    }

    private var copy: SettingsCopy {
        switch uiLanguage {
        case .english:
            SettingsCopy(
                settingsTitle: "Settings",
                saveButton: "Save",
                shortcutSection: "Shortcut",
                shortcutKeyLabel: "Shortcut Key",
                modifierLabel: "Modifiers",
                controlLabel: "Control",
                optionLabel: "Option",
                commandLabel: "Command",
                shiftLabel: "Shift",
                currentShortcutLabel: "Current Shortcut",
                shortcutHelp: "Choose one key and a modifier combination for the global shortcut.",
                languageSection: "Language",
                languageHelp: "Choose the app language for the settings UI.",
                voiceSection: "Voice",
                languageLabel: "Language",
                voiceLabel: "Voice",
                defaultVoiceLabel: "Default",
                voiceHelp: "Select an English voice for text-to-speech.",
                rateSection: "Speech Rate",
                rateLabel: "Rate",
                rateHelp: "Adjust the speed of speech (slower ← → faster)",
                pitchSection: "Speech Pitch",
                pitchLabel: "Pitch",
                pitchHelp: "Adjust the pitch of speech (lower ← → higher)",
                testSpeechButton: "Test Speech",
                resetDefaultsButton: "Reset to Defaults",
                speechTab: "Speech",
                grammarTab: "Grammar",
                grammarShortcutSection: "Grammar Shortcut",
                modelSection: "Model",
                apiModeLabel: "API Mode",
                modelLabel: "Model",
                baseURLLabel: "Base URL",
                apiKeyLabel: "API Key",
                maxTokensLabel: "Max Tokens",
                systemPromptSection: "System Prompt",
                resetGrammarDefaultsButton: "Reset Grammar Defaults",
                duplicateShortcutMessage: "Speech and Grammar shortcuts must be different.",
                okButton: "OK"
            )
        case .chinese:
            SettingsCopy(
                settingsTitle: "设置",
                saveButton: "保存",
                shortcutSection: "快捷键",
                shortcutKeyLabel: "快捷键按键",
                modifierLabel: "修饰键",
                controlLabel: "Control",
                optionLabel: "Option",
                commandLabel: "Command",
                shiftLabel: "Shift",
                currentShortcutLabel: "当前快捷键",
                shortcutHelp: "请选择一个按键和一组修饰键作为全局快捷键。",
                languageSection: "语言",
                languageHelp: "选择设置界面的显示语言。",
                voiceSection: "语音",
                languageLabel: "语言",
                voiceLabel: "声音",
                defaultVoiceLabel: "默认",
                voiceHelp: "请选择一个英文语音用于朗读。",
                rateSection: "语速",
                rateLabel: "速度",
                rateHelp: "调整朗读速度（慢 ← → 快）",
                pitchSection: "音调",
                pitchLabel: "音调",
                pitchHelp: "调整朗读音调（低 ← → 高）",
                testSpeechButton: "测试朗读",
                resetDefaultsButton: "恢复默认设置",
                speechTab: "朗读",
                grammarTab: "语法",
                grammarShortcutSection: "语法快捷键",
                modelSection: "模型",
                apiModeLabel: "API 模式",
                modelLabel: "模型",
                baseURLLabel: "基础 URL",
                apiKeyLabel: "API 密钥",
                maxTokensLabel: "最大令牌数",
                systemPromptSection: "系统提示词",
                resetGrammarDefaultsButton: "恢复语法默认设置",
                duplicateShortcutMessage: "朗读和语法快捷键不能相同。",
                okButton: "好的"
            )
        }
    }

    private func localizedTitle(for language: SpeechSettings.LanguageOption) -> String {
        switch uiLanguage {
        case .english:
            return language.title
        case .chinese:
            switch language {
            case .english:
                return "英文"
            case .chinese:
                return "中文"
            }
        }
    }

    private func localizedTitle(for mode: GrammarSettings.APIMode) -> String {
        switch uiLanguage {
        case .english:
            return mode.title
        case .chinese:
            switch mode {
            case .openAICompatible:
                return "OpenAI 兼容"
            case .direct:
                return "直接 API"
            }
        }
    }

    private func previewVoiceIfNeeded(_ newVoiceIdentifier: String?) {
        guard newVoiceIdentifier != lastPreviewedVoiceIdentifier else { return }

        lastPreviewedVoiceIdentifier = newVoiceIdentifier
        ttsService.speak(
            text: "hello",
            voiceIdentifier: newVoiceIdentifier,
            fallbackVoice: previewVoice,
            rate: draftRate,
            pitch: draftPitch
        )
    }
}

private struct SettingsCopy {
    let settingsTitle: String
    let saveButton: String
    let shortcutSection: String
    let shortcutKeyLabel: String
    let modifierLabel: String
    let controlLabel: String
    let optionLabel: String
    let commandLabel: String
    let shiftLabel: String
    let currentShortcutLabel: String
    let shortcutHelp: String
    let languageSection: String
    let languageHelp: String
    let voiceSection: String
    let languageLabel: String
    let voiceLabel: String
    let defaultVoiceLabel: String
    let voiceHelp: String
    let rateSection: String
    let rateLabel: String
    let rateHelp: String
    let pitchSection: String
    let pitchLabel: String
    let pitchHelp: String
    let testSpeechButton: String
    let resetDefaultsButton: String
    let speechTab: String
    let grammarTab: String
    let grammarShortcutSection: String
    let modelSection: String
    let apiModeLabel: String
    let modelLabel: String
    let baseURLLabel: String
    let apiKeyLabel: String
    let maxTokensLabel: String
    let systemPromptSection: String
    let resetGrammarDefaultsButton: String
    let duplicateShortcutMessage: String
    let okButton: String
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
