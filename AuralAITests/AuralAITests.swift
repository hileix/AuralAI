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

    @Test func grammarHistoryPersistsNewestEntriesWithinLimit() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("GrammarHistory.json")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = GrammarHistoryStore(fileURL: fileURL, maxEntries: 2)
        let response = GrammarAIResponse(
            translation: "Translation",
            errors: "An error",
            options: ["Suggestion"]
        )

        store.add(originalText: "First", response: response)
        store.add(originalText: "Second", response: response)
        store.add(originalText: "Third", response: response)

        #expect(store.entries.map(\.originalText) == ["Third", "Second"])

        let reloadedStore = GrammarHistoryStore(fileURL: fileURL, maxEntries: 2)
        #expect(reloadedStore.entries == store.entries)
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
