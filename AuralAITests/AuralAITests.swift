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

    @Test @MainActor func grammarInputBadgeCannotHideWhileLoading() throws {
        let badge = GrammarInputBadge.shared
        defer {
            badge.stopLoading()
            badge.hide()
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

    @Test func grammarHistoryPersistsMoreThanOneHundredEntries() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("GrammarHistory.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = GrammarHistoryStore(fileURL: fileURL)
        let response = GrammarAIResponse(
            translation: "Translation",
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

        let response = GrammarAIResponse(
            translation: nil,
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
            response: GrammarAIResponse(
                translation: nil,
                errors: "Older result",
                options: ["Older suggestion"]
            )
        )
        store.add(
            originalText: "Improve this sentence.",
            response: GrammarAIResponse(
                translation: nil,
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

    @Test func incompleteUnstructuredResponseHasNoPartialResult() {
        let parsed = GrammarAIService.shared.parsePartialResponse(from: "Still generating")

        #expect(parsed == nil)
    }

}
