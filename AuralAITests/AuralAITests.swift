//
//  AuralAITests.swift
//  AuralAITests
//
//  Created by mac on 2026/3/21.
//

import Testing
import Foundation
@testable import AuralAI

struct AuralAITests {

    @Test func convertsAccessibilityFrameToAppKitCoordinates() {
        let frame = FocusedTextInputService.appKitFrame(
            position: CGPoint(x: 120, y: 90),
            size: CGSize(width: 480, height: 140),
            primaryScreenMaxY: 1_080
        )

        #expect(frame == CGRect(x: 120, y: 850, width: 480, height: 140))
    }

    @Test func focusedInputContentRequiresNonWhitespaceText() {
        #expect(!FocusedTextInputService.hasMeaningfulContent(""))
        #expect(!FocusedTextInputService.hasMeaningfulContent(" "))
        #expect(!FocusedTextInputService.hasMeaningfulContent("  \n"))
        #expect(!FocusedTextInputService.hasMeaningfulContent("\t\n "))
        #expect(FocusedTextInputService.hasMeaningfulContent("Hello"))
        #expect(FocusedTextInputService.hasMeaningfulContent(" Hello "))
    }

    @Test func grammarInputBadgeIsVisibleByDefault() {
        #expect(GrammarSettings.CodableSettings.defaults.isInputBadgeVisible)
    }

    @Test @MainActor func grammarInputBadgeCannotHideWhileLoading() throws {
        let badge = GrammarInputBadge.shared
        let originalVisibility = GrammarSettings.shared.isInputBadgeVisible
        GrammarSettings.shared.isInputBadgeVisible = true
        defer {
            badge.stopLoading()
            badge.hide()
            GrammarSettings.shared.isInputBadgeVisible = originalVisibility
        }

        badge.show(at: NSPoint(x: 100, y: 100), onClick: {})
        let visibleCenter = try #require(badge.centerPoint)
        badge.showLoading()

        badge.hide()
        badge.show(at: NSPoint(x: 300, y: 300), onClick: {})

        #expect(badge.isLoading)
        #expect(badge.centerPoint == visibleCenter)

        badge.stopLoading()
        badge.hide()
        #expect(badge.centerPoint == nil)
    }

    @Test @MainActor func grammarInputBadgeTemporarilyShowsLoadingWhenDisabled() throws {
        let badge = GrammarInputBadge.shared
        let originalVisibility = GrammarSettings.shared.isInputBadgeVisible
        GrammarSettings.shared.isInputBadgeVisible = false
        defer {
            badge.stopLoading()
            badge.hide()
            GrammarSettings.shared.isInputBadgeVisible = originalVisibility
        }

        badge.showLoading(at: NSPoint(x: 100, y: 100), onClick: {})

        #expect(badge.isLoading)
        #expect(badge.centerPoint != nil)

        badge.stopLoading()
        #expect(!badge.isLoading)
        #expect(badge.centerPoint == nil)
    }

    @Test func grammarHistoryPersistsMoreThanOneHundredEntries() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("GrammarHistory.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = GrammarHistoryStore(fileURL: fileURL)
        let response = GrammarOptimizationResult(
            errors: "An error",
            options: ["Suggestion"]
        )

        for index in 0..<125 {
            store.add(originalText: "Entry \(index)", response: response)
        }

        #expect(store.entries.count == 125)

        let reloadedStore = GrammarHistoryStore(fileURL: fileURL)
        #expect(reloadedStore.entries.count == 125)
        #expect(Set(reloadedStore.entries.map(\.originalText)).count == 125)
    }

    @Test func grammarHistoryDeletesAndClearsEntries() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("GrammarHistory.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let response = GrammarOptimizationResult(
            errors: nil,
            options: ["Suggestion"]
        )
        let store = GrammarHistoryStore(fileURL: fileURL)
        store.add(originalText: "First", response: response)
        store.add(originalText: "Second", response: response)

        let entryToDelete = try #require(store.entries.last)
        store.delete(entryToDelete)
        #expect(store.entries.map(\.originalText) == ["Second"])

        store.clear()
        #expect(store.entries.isEmpty)
        #expect(GrammarHistoryStore(fileURL: fileURL).entries.isEmpty)
    }

    @Test func grammarHistoryReturnsNewestTrimmedExactMatch() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("GrammarHistory.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = GrammarHistoryStore(fileURL: fileURL)
        store.add(
            originalText: "  Improve this sentence.\n",
            response: GrammarOptimizationResult(
                errors: "Older result",
                options: ["Older suggestion"]
            )
        )
        store.add(
            originalText: "Improve this sentence.",
            response: GrammarOptimizationResult(
                errors: "Newest result",
                options: ["Newest suggestion"]
            )
        )

        let response = try #require(store.response(matching: "\nImprove this sentence.  "))
        #expect(response.errors == "Newest result")
        #expect(response.options == ["Newest suggestion"])
        #expect(store.response(matching: "improve this sentence.") == nil)
    }

    @Test func parsesOpenAIStreamingTextDelta() throws {
        let data = try #require(
            #"{"choices":[{"delta":{"content":"Hello"}}]}"#.data(using: .utf8)
        )

        #expect(GrammarAIService.streamingTextDelta(from: data) == "Hello")
    }

    @Test func parsesAnthropicStreamingTextDelta() throws {
        let data = try #require(
            #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#.data(using: .utf8)
        )

        #expect(GrammarAIService.streamingTextDelta(from: data) == "Hello")
    }

    @Test func parsesStreamingFinishReasons() throws {
        let openAIData = try #require(
            #"{"choices":[{"delta":{},"finish_reason":"length"}]}"#.data(using: .utf8)
        )
        let directData = try #require(
            #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#.data(using: .utf8)
        )

        #expect(GrammarAIService.streamingFinishReason(from: openAIData) == "length")
        #expect(GrammarAIService.streamingFinishReason(from: directData) == "max_tokens")
    }

    @Test func incompleteUnstructuredResponseHasNoPartialResult() {
        let parsed = GrammarAIService.shared.parsePartialResponse(from: "Still generating")

        #expect(parsed == nil)
    }

    @Test func grammarResponseDoesNotExposeTranslation() {
        let parsed = GrammarAIService.shared.parseResponse(
            from: """
                翻译：这段内容不应出现在语法结果中
                错误：Missing an article.
                选项1：This is the improved sentence.
                """
        )

        #expect(parsed.errors == "Missing an article.")
        #expect(parsed.options == ["This is the improved sentence."])
    }

    @Test func parsesTranslationResponseIndependently() throws {
        let result = try TranslationService.shared.parseResponse(
            "翻译：这是一个自然的翻译。",
            originalText: "This is a natural translation."
        )

        #expect(result.originalText == "This is a natural translation.")
        #expect(result.translatedText == "这是一个自然的翻译。")
    }

    @Test func rejectsEmptyTranslationResponse() {
        #expect(throws: TranslationError.self) {
            try TranslationService.shared.parseResponse(
                "翻译：   ",
                originalText: "This response should not be cached."
            )
        }
    }

    @Test func rejectsTruncatedTranslationAPIResponses() throws {
        let openAIData = try #require(
            #"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#
                .data(using: .utf8)
        )
        let directData = try #require(
            #"{"content":[{"text":"partial"}],"stop_reason":"max_tokens"}"#
                .data(using: .utf8)
        )

        #expect(throws: TranslationError.self) {
            try TranslationService.shared.parseOpenAIResponse(openAIData)
        }
        #expect(throws: TranslationError.self) {
            try TranslationService.shared.parseDirectResponse(directData)
        }
    }

    @Test func translationResponseTokenBudgetScalesWithInputLength() {
        let shortBudget = TranslationService.dynamicMaxTokens(for: "Translate this sentence.")
        let longBudget = TranslationService.dynamicMaxTokens(
            for: String(repeating: "这是一段需要翻译的长文本。", count: 500)
        )

        #expect(shortBudget == 1_024)
        #expect(longBudget > shortBudget)
        #expect(longBudget == 8_192)
    }

    @Test func translationHistoryPersistsDeletesAndClearsEntries() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("TranslationHistory.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = TranslationHistoryStore(fileURL: fileURL)
        store.add(TranslationResult(originalText: "Hello", translatedText: "你好"))
        store.add(TranslationResult(originalText: "Goodbye", translatedText: "再见"))

        let reloadedStore = TranslationHistoryStore(fileURL: fileURL)
        #expect(reloadedStore.entries.map(\.originalText) == ["Goodbye", "Hello"])
        #expect(reloadedStore.result(matching: " Hello ")?.translatedText == "你好")

        let entry = try #require(reloadedStore.entries.first)
        reloadedStore.delete(entry)
        #expect(reloadedStore.entries.map(\.originalText) == ["Hello"])

        reloadedStore.clear()
        #expect(TranslationHistoryStore(fileURL: fileURL).entries.isEmpty)
    }

    @Test func invalidLegacyGrammarHistoryStartsEmpty() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("GrammarOptimizationHistory.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(#"[{"legacy":"history"}]"#.utf8).write(to: fileURL)

        #expect(GrammarHistoryStore(fileURL: fileURL).entries.isEmpty)
    }

    @Test func grammarResponseTokenBudgetScalesWithInputLength() {
        let shortBudget = GrammarAIService.dynamicMaxTokens(for: "This sentence needs work.")
        let mediumBudget = GrammarAIService.dynamicMaxTokens(
            for: String(repeating: "This is a longer sentence that needs improvement. ", count: 20)
        )
        let longBudget = GrammarAIService.dynamicMaxTokens(
            for: String(repeating: "这是一段需要翻译和改进的长文本。", count: 500)
        )

        #expect(shortBudget == 1_024)
        #expect(mediumBudget > shortBudget)
        #expect(longBudget > mediumBudget)
        #expect(longBudget == 8_192)
    }

    @Test func systemPromptReducesOnlyAvailableResponseCapacity() throws {
        let text = "This sentence needs work."
        let shortPromptCapacity = try GrammarAIService.maximumAllowedResponseTokens(
            for: text,
            systemPrompt: "Improve the text."
        )
        let longPromptCapacity = try GrammarAIService.maximumAllowedResponseTokens(
            for: text,
            systemPrompt: String(repeating: "规则", count: 12_500)
        )

        #expect(GrammarAIService.dynamicMaxTokens(for: text) == 1_024)
        #expect(shortPromptCapacity == 8_192)
        #expect(longPromptCapacity < shortPromptCapacity)
    }

    @Test func rejectsRequestWhenPromptLeavesNoSafeResponseBudget() {
        #expect(throws: GrammarAIError.self) {
            try GrammarAIService.maximumAllowedResponseTokens(
                for: "Short text",
                systemPrompt: String(repeating: "规则", count: 16_000)
            )
        }
    }

}
