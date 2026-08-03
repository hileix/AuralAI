//
//  ClipboardMonitor.swift
//  AuralAI
//
//  Created by AuralAI Migration
//

import Foundation
import AppKit

/// Service for monitoring and reading clipboard/pasteboard content
class ClipboardMonitor: ObservableObject {
    typealias PasteboardContents = [[NSPasteboard.PasteboardType: Data]]

    static let shared = ClipboardMonitor()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = 0
    private var timer: Timer?

    @Published var currentClipboardText: String?

    private init() {
        lastChangeCount = pasteboard.changeCount
    }

    /// Start monitoring clipboard for changes
    func startMonitoring(interval: TimeInterval = 0.5, onTextCopied: @escaping (String) -> Void) {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let currentChangeCount = self.pasteboard.changeCount

            if currentChangeCount != self.lastChangeCount {
                self.lastChangeCount = currentChangeCount

                if let text = self.readClipboardText(), !text.isEmpty {
                    DispatchQueue.main.async {
                        self.currentClipboardText = text
                        onTextCopied(text)
                    }
                }
            }
        }

        print("Clipboard monitoring started")
    }

    /// Stop monitoring clipboard
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        print("Clipboard monitoring stopped")
    }

    /// Read text from clipboard immediately
    func readClipboardText() -> String? {
        if let text = pasteboard.string(forType: .string) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    func currentChangeCount() -> Int {
        pasteboard.changeCount
    }

    func snapshotContents() -> PasteboardContents {
        pasteboard.pasteboardItems?.map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                contents[type] = item.data(forType: type)
            }
            return contents
        } ?? []
    }

    func restoreContents(_ contents: PasteboardContents) {
        pasteboard.clearContents()
        let items = contents.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    /// Write text to clipboard
    func writeToClipboard(text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    deinit {
        stopMonitoring()
    }
}
