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

    #if os(macOS)
    private enum SettingsTab {
        case speech
        case grammar
        case history
    }
    #endif

    @Environment(\.dismiss) private var dismiss
    @StateObject private var settings = SpeechSettings.shared
    @StateObject private var grammarSettings = GrammarSettings.shared
    @StateObject private var ttsService = TTSService.shared
    #if os(macOS)
    @StateObject private var grammarHistoryStore = GrammarHistoryStore.shared
    #endif

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
    #if os(macOS)
    @State private var selectedTab: SettingsTab = .speech
    @State private var isShowingClearHistoryConfirmation = false
    #endif

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

    private func resetSpeechSettings() {
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
    }

    private func resetGrammarSettings() {
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
                    resetSpeechSettings()
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
                    resetGrammarSettings()
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
        HStack(spacing: 0) {
            macOSSidebar
            Divider()

            VStack(spacing: 0) {
                macOSHeader
                Divider()

                Group {
                    switch selectedTab {
                    case .speech:
                        macOSSpeechSettings
                    case .grammar:
                        macOSGrammarSettings
                    case .history:
                        macOSGrammarHistory
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color(red: 0.12, green: 0.49, blue: 0.91))
        .confirmationDialog(
            copy.clearHistoryConfirmationTitle,
            isPresented: $isShowingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button(copy.clearHistoryButton, role: .destructive) {
                grammarHistoryStore.clear()
            }
            Button(copy.cancelButton, role: .cancel) {}
        } message: {
            Text(copy.clearHistoryConfirmationMessage)
        }
        .alert(copy.settingsTitle, isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button(copy.okButton, role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var macOSSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(appDisplayName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(copy.settingsTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)

            VStack(spacing: 6) {
                macOSSidebarButton(
                    title: copy.speechTab,
                    systemImage: "speaker.wave.2.fill",
                    shortcut: draftHotkeyDisplayString,
                    tab: .speech
                )

                macOSSidebarButton(
                    title: copy.grammarTab,
                    systemImage: "textformat",
                    shortcut: draftGrammarHotkeyDisplayString,
                    tab: .grammar
                )

                macOSSidebarButton(
                    title: copy.historyTab,
                    systemImage: "clock.arrow.circlepath",
                    tab: .history
                )
            }
            .padding(.horizontal, 10)

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(hasChanges ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(hasChanges ? copy.unsavedChangesLabel : copy.savedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .frame(width: 188)
        .background(.ultraThinMaterial)
    }

    private func macOSSidebarButton(
        title: String,
        systemImage: String,
        shortcut: String? = nil,
        tab: SettingsTab
    ) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)

                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.13) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(sidebarAccessibilityIdentifier(for: tab))
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private func sidebarAccessibilityIdentifier(for tab: SettingsTab) -> String {
        switch tab {
        case .speech:
            return "settings.tab.speech"
        case .grammar:
            return "settings.tab.grammar"
        case .history:
            return "settings.tab.history"
        }
    }

    private var macOSHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTabTitle)
                    .font(.title2.weight(.semibold))
                Text(copy.settingsTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if selectedTab == .history {
                Button(role: .destructive) {
                    isShowingClearHistoryConfirmation = true
                } label: {
                    Label(copy.clearHistoryButton, systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(grammarHistoryStore.entries.isEmpty)
            } else {
                Button {
                    saveChanges()
                } label: {
                    Label(copy.saveButton, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!hasChanges)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 72)
    }

    private var selectedTabTitle: String {
        switch selectedTab {
        case .speech:
            return copy.speechTab
        case .grammar:
            return copy.grammarTab
        case .history:
            return copy.historyTab
        }
    }

    private var macOSSpeechSettings: some View {
        ScrollView {
            VStack(spacing: 0) {
                macOSSection(title: copy.shortcutSection, systemImage: "command") {
                    macOSSettingsRow(title: copy.shortcutKeyLabel, help: copy.shortcutHelp) {
                        HStack(spacing: 10) {
                            TextField(copy.shortcutKeyLabel, text: $hotkeyInput)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                                .frame(width: 52)
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
                            .labelsHidden()
                            .frame(width: 210)
                        }
                    }

                    macOSSettingsRow(title: copy.currentShortcutLabel) {
                        shortcutBadge(draftHotkeyDisplayString, isError: false)
                    }
                }

                Divider()

                macOSSection(title: copy.languageSection, systemImage: "globe") {
                    macOSSettingsRow(title: copy.languageLabel, help: copy.languageHelp) {
                        Picker(copy.languageLabel, selection: $draftLanguageRawValue) {
                            ForEach(SpeechSettings.LanguageOption.allCases) { language in
                                Text(localizedTitle(for: language)).tag(language.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 272)
                    }
                }

                Divider()

                macOSSection(title: copy.voiceSection, systemImage: "waveform") {
                    macOSSettingsRow(title: copy.voiceLabel, help: copy.voiceHelp) {
                        Picker(copy.voiceLabel, selection: $draftVoiceIdentifier) {
                            Text(copy.defaultVoiceLabel).tag(nil as String?)
                            ForEach(settings.englishVoices(), id: \.identifier) { voice in
                                Text("\(voice.name) (\(voice.language))")
                                    .tag(voice.identifier as String?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 272)
                        .onChange(of: draftVoiceIdentifier) { _, newValue in
                            previewVoiceIfNeeded(newValue)
                        }
                    }
                }

                Divider()

                macOSSection(title: copy.deliverySection, systemImage: "slider.horizontal.3") {
                    macOSSettingsRow(title: copy.rateLabel, help: copy.rateHelp) {
                        HStack(spacing: 12) {
                            Slider(
                                value: $draftRate,
                                in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate
                            )
                            Text(String(format: "%.2f", draftRate))
                                .font(.system(.body, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                        .frame(width: 272)
                    }

                    macOSSettingsRow(title: copy.pitchLabel, help: copy.pitchHelp) {
                        HStack(spacing: 12) {
                            Slider(value: $draftPitch, in: 0.5...2.0)
                            Text(String(format: "%.2f", draftPitch))
                                .font(.system(.body, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                        .frame(width: 272)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Button(action: testSpeech) {
                        Label(copy.testSpeechButton, systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Spacer()

                    Button(role: .destructive, action: resetSpeechSettings) {
                        Label(copy.resetDefaultsButton, systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                .padding(.vertical, 22)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var macOSGrammarSettings: some View {
        ScrollView {
            VStack(spacing: 0) {
                macOSSection(title: copy.grammarShortcutSection, systemImage: "command") {
                    macOSSettingsRow(title: copy.shortcutKeyLabel) {
                        HStack(spacing: 10) {
                            TextField(copy.shortcutKeyLabel, text: $grammarHotkeyInput)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                                .frame(width: 52)
                                .onChange(of: grammarHotkeyInput) { _, newValue in
                                    let normalized = GrammarSettings.supportedHotkeyKey(from: newValue)
                                        ?? GrammarSettings.defaultHotkeyKey
                                    grammarHotkeyInput = normalized
                                    draftGrammarHotkeyKey = normalized
                                }

                            Picker(copy.modifierLabel, selection: $draftGrammarHotkeyModifiersRawValue) {
                                ForEach(grammarModifierOptions, id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 210)
                        }
                    }

                    macOSSettingsRow(title: copy.currentShortcutLabel) {
                        shortcutBadge(draftGrammarHotkeyDisplayString, isError: hasDuplicateHotkeys)
                    }

                    if hasDuplicateHotkeys {
                        Label(copy.duplicateShortcutMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 178)
                    }
                }

                Divider()

                macOSSection(title: copy.modelSection, systemImage: "cpu") {
                    Picker(copy.apiModeLabel, selection: $draftGrammarAPIModeRawValue) {
                        ForEach(GrammarSettings.APIMode.allCases) { mode in
                            Text(localizedTitle(for: mode)).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    macOSSettingsRow(title: copy.modelLabel) {
                        TextField(copy.modelLabel, text: $draftGrammarModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 272)
                    }

                    macOSSettingsRow(title: copy.baseURLLabel) {
                        TextField(copy.baseURLLabel, text: $draftGrammarBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 272)
                    }

                    macOSSettingsRow(title: copy.apiKeyLabel) {
                        SecureField(copy.apiKeyLabel, text: $draftGrammarAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 272)
                    }

                    macOSSettingsRow(title: copy.maxTokensLabel) {
                        TextField("1024", value: $draftGrammarMaxTokens, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 92)
                    }
                }

                Divider()

                macOSSection(title: copy.systemPromptSection, systemImage: "text.alignleft") {
                    TextEditor(text: $draftGrammarPrompt)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 190)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                }

                Divider()

                HStack {
                    Spacer()
                    Button(role: .destructive, action: resetGrammarSettings) {
                        Label(copy.resetGrammarDefaultsButton, systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                .padding(.vertical, 22)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var macOSGrammarHistory: some View {
        ScrollView {
            if grammarHistoryStore.entries.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)

                    Text(copy.emptyHistoryTitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
                .accessibilityIdentifier("settings.history.empty")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(grammarHistoryStore.entries) { entry in
                        GrammarHistoryRow(entry: entry, copy: copy) {
                            grammarHistoryStore.delete(entry)
                        }
                    }
                }
                .padding(.vertical, 22)
            }
        }
        .padding(.horizontal, 30)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .accessibilityIdentifier("settings.history")
    }

    private func macOSSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
        }
        .padding(.vertical, 24)
    }

    private func macOSSettingsRow<Control: View>(
        title: String,
        help: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: help == nil ? .center : .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)

                if let help {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
        }
    }

    private func shortcutBadge(_ shortcut: String, isError: Bool) -> some View {
        Text(shortcut)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .foregroundStyle(isError ? Color.red : Color.primary)
            .background(isError ? Color.red.opacity(0.1) : Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isError ? Color.red.opacity(0.4) : Color.primary.opacity(0.12), lineWidth: 1)
            }
    }
    #endif

    private var uiLanguage: UILanguage {
        draftLanguageRawValue == SpeechSettings.LanguageOption.chinese.rawValue ? .chinese : .english
    }

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "AuralAI"
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
                deliverySection: "Delivery",
                testSpeechButton: "Test Speech",
                resetDefaultsButton: "Reset to Defaults",
                speechTab: "Speech",
                grammarTab: "Grammar",
                historyTab: "History",
                savedLabel: "All changes saved",
                unsavedChangesLabel: "Unsaved changes",
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
                emptyHistoryTitle: "No writing history yet",
                originalTextTitle: "Original text",
                historyResultsTitle: "View results",
                historyTranslationTitle: "Translation",
                historyErrorsTitle: "What to fix",
                historySuggestionsTitle: "Suggestions",
                deleteHistoryButton: "Delete Entry",
                clearHistoryButton: "Clear History",
                clearHistoryConfirmationTitle: "Clear all writing history?",
                clearHistoryConfirmationMessage: "This can't be undone.",
                cancelButton: "Cancel",
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
                deliverySection: "朗读效果",
                testSpeechButton: "测试朗读",
                resetDefaultsButton: "恢复默认设置",
                speechTab: "朗读",
                grammarTab: "语法",
                historyTab: "历史记录",
                savedLabel: "所有更改均已保存",
                unsavedChangesLabel: "有未保存的更改",
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
                emptyHistoryTitle: "暂无写作历史记录",
                originalTextTitle: "原始文本",
                historyResultsTitle: "查看结果",
                historyTranslationTitle: "翻译",
                historyErrorsTitle: "需要修改",
                historySuggestionsTitle: "建议",
                deleteHistoryButton: "删除记录",
                clearHistoryButton: "清空历史",
                clearHistoryConfirmationTitle: "清空所有写作历史？",
                clearHistoryConfirmationMessage: "此操作无法撤销。",
                cancelButton: "取消",
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

#if os(macOS)
private struct GrammarHistoryRow: View {
    let entry: GrammarHistoryEntry
    let copy: SettingsCopy
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(entry.timestamp, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(copy.deleteHistoryButton)
                .accessibilityLabel(copy.deleteHistoryButton)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(copy.originalTextTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(entry.originalText)
                    .font(.body)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 16) {
                    if let translation = entry.translation {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(copy.historyTranslationTitle, systemImage: "character.book.closed")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                            Text(translation)
                                .textSelection(.enabled)
                        }
                    }

                    if let errors = entry.errors {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(copy.historyErrorsTitle, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(errors)
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label(copy.historySuggestionsTitle, systemImage: "text.badge.checkmark")
                            .font(.caption.weight(.semibold))

                        ForEach(Array(entry.options.enumerated()), id: \.offset) { index, option in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 20)
                                Text(option)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .font(.callout)
                .padding(.top, 12)
            } label: {
                Label(copy.historyResultsTitle, systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        }
        .accessibilityIdentifier("settings.history.entry.\(entry.id.uuidString)")
    }
}
#endif

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
    let deliverySection: String
    let testSpeechButton: String
    let resetDefaultsButton: String
    let speechTab: String
    let grammarTab: String
    let historyTab: String
    let savedLabel: String
    let unsavedChangesLabel: String
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
    let emptyHistoryTitle: String
    let originalTextTitle: String
    let historyResultsTitle: String
    let historyTranslationTitle: String
    let historyErrorsTitle: String
    let historySuggestionsTitle: String
    let deleteHistoryButton: String
    let clearHistoryButton: String
    let clearHistoryConfirmationTitle: String
    let clearHistoryConfirmationMessage: String
    let cancelButton: String
    let okButton: String
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
