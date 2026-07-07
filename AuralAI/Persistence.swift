//
//  Persistence.swift
//  AuralAI
//
//  Created by mac on 2026/3/21.
//

import CoreData
import Foundation

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for i in 0..<10 {
            let newHistory = SpeechHistory(context: viewContext)
            newHistory.id = UUID()
            newHistory.text = "Sample speech history item \(i + 1)"
            newHistory.timestamp = Date().addingTimeInterval(-Double(i * 3600))
            newHistory.source = "manual"
            newHistory.voice = "com.apple.ttsbundle.Samantha-compact"
            newHistory.duration = 2.5
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "AuralAI")
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Missing persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.url = Self.defaultStoreURL()
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Helper Methods

    /// Save speech history to CoreData
    func saveSpeechHistory(text: String, source: String, voice: String, duration: Double = 0.0) {
        let context = container.viewContext
        let newHistory = SpeechHistory(context: context)
        newHistory.id = UUID()
        newHistory.text = text
        newHistory.timestamp = Date()
        newHistory.source = source
        newHistory.voice = voice
        newHistory.duration = duration

        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            print("Error saving speech history: \(nsError), \(nsError.userInfo)")
        }
    }

    /// Fetch recent speech history
    func fetchRecentHistory(limit: Int = 10) -> [SpeechHistory] {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<SpeechHistory> = SpeechHistory.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \SpeechHistory.timestamp, ascending: false)]
        fetchRequest.fetchLimit = limit

        do {
            return try context.fetch(fetchRequest)
        } catch {
            print("Error fetching speech history: \(error)")
            return []
        }
    }

    /// Delete all speech history
    func deleteAllHistory() {
        let context = container.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = SpeechHistory.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs

        do {
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            if let deletedObjectIDs = result?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: deletedObjectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            }
            try context.save()
        } catch {
            print("Error deleting speech history: \(error)")
        }
    }

    private static func defaultStoreURL() -> URL {
        let fileManager = FileManager.default
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.xiaolei.AuralAI"

        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not resolve Application Support directory")
        }

        let directoryURL = appSupportURL.appendingPathComponent(bundleIdentifier, isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            fatalError("Could not create persistent store directory: \(error)")
        }

        return directoryURL.appendingPathComponent("AuralAI.sqlite")
    }
}
