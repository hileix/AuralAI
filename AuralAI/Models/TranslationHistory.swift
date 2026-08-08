//
//  TranslationHistory.swift
//  AuralAI
//

import Combine
import Foundation

struct TranslationResult: Codable, Equatable {
    let originalText: String
    let translatedText: String
}

struct TranslationHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let timestamp: Date

    init(id: UUID = UUID(), result: TranslationResult, timestamp: Date = Date()) {
        self.id = id
        originalText = result.originalText
        translatedText = result.translatedText
        self.timestamp = timestamp
    }

    var result: TranslationResult {
        TranslationResult(originalText: originalText, translatedText: translatedText)
    }
}

final class TranslationHistoryStore: ObservableObject {
    static let shared = TranslationHistoryStore()

    @Published private(set) var entries: [TranslationHistoryEntry] = []

    private let fileURL: URL

    init(fileURL: URL = TranslationHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        entries = loadEntries()
    }

    func add(_ result: TranslationResult) {
        entries.insert(TranslationHistoryEntry(result: result), at: 0)
        saveEntries()
    }

    func result(matching originalText: String) -> TranslationResult? {
        let trimmedText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let entry = entries.first(where: {
                  $0.originalText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedText
              }) else {
            return nil
        }
        return entry.result
    }

    func delete(_ entry: TranslationHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    func clear() {
        entries.removeAll()
        saveEntries()
    }

    #if DEBUG
    func usePreviewEntries(_ previewEntries: [TranslationHistoryEntry]) {
        entries = previewEntries
    }
    #endif

    private func loadEntries() -> [TranslationHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([TranslationHistoryEntry].self, from: data)
                .sorted { $0.timestamp > $1.timestamp }
        } catch {
            print("Could not load translation history: \(error.localizedDescription)")
            return []
        }
    }

    private func saveEntries() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Could not save translation history: \(error.localizedDescription)")
        }
    }

    private static func defaultFileURL() -> URL {
        let fileManager = FileManager.default
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.xiaolei.AuralAI"
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("TranslationHistory.json")
    }
}
