//
//  GrammarHistory.swift
//  AuralAI
//

import Combine
import Foundation

struct GrammarHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let originalText: String
    let translation: String?
    let errors: String?
    let options: [String]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        originalText: String,
        response: GrammarAIResponse,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.originalText = originalText
        translation = response.translation
        errors = response.errors
        options = response.options
        self.timestamp = timestamp
    }
}

final class GrammarHistoryStore: ObservableObject {
    static let shared = GrammarHistoryStore()

    @Published private(set) var entries: [GrammarHistoryEntry] = []

    private let fileURL: URL
    private let maxEntries: Int

    init(fileURL: URL = GrammarHistoryStore.defaultFileURL(), maxEntries: Int = 100) {
        self.fileURL = fileURL
        self.maxEntries = max(1, maxEntries)
        entries = loadEntries()
    }

    func add(originalText: String, response: GrammarAIResponse) {
        entries.insert(
            GrammarHistoryEntry(originalText: originalText, response: response),
            at: 0
        )

        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }

        saveEntries()
    }

    func response(matching originalText: String) -> GrammarAIResponse? {
        let trimmedText = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let entry = entries.first(where: {
                  $0.originalText.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedText
              }) else {
            return nil
        }

        return GrammarAIResponse(
            translation: entry.translation,
            errors: entry.errors,
            options: entry.options
        )
    }

    func delete(_ entry: GrammarHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    func clear() {
        entries.removeAll()
        saveEntries()
    }

    #if DEBUG
    func usePreviewEntries(_ previewEntries: [GrammarHistoryEntry]) {
        entries = previewEntries
    }
    #endif

    private func loadEntries() -> [GrammarHistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        do {
            return try JSONDecoder().decode([GrammarHistoryEntry].self, from: data)
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(maxEntries)
                .map { $0 }
        } catch {
            print("Could not load grammar history: \(error.localizedDescription)")
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
            print("Could not save grammar history: \(error.localizedDescription)")
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
            .appendingPathComponent("GrammarHistory.json")
    }
}
