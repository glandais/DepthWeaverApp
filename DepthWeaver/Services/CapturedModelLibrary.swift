#if os(iOS)
import Foundation
import os

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "CapturedModelLibrary")

@MainActor
final class CapturedModelLibrary: ObservableObject {
    static let shared = CapturedModelLibrary()

    struct Entry: Codable, Identifiable, Hashable {
        let id: UUID
        var displayName: String
        let createdAt: Date
        var fileName: String
    }

    @Published private(set) var entries: [Entry] = []

    private let rootURL: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.rootURL = docs.appendingPathComponent("CapturedModels", isDirectory: true)
        self.indexURL = rootURL.appendingPathComponent("captures.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    func load() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            logger.error("failed to create CapturedModels dir: \(error.localizedDescription)")
            return
        }
        guard fileManager.fileExists(atPath: indexURL.path) else {
            entries = []
            return
        }
        do {
            let data = try Data(contentsOf: indexURL)
            let parsed = try decoder.decode([Entry].self, from: data)
            entries = parsed.sorted { $0.createdAt > $1.createdAt }
        } catch {
            logger.error("failed to decode captures.json: \(error.localizedDescription)")
            entries = []
        }
    }

    func save(usdzAt sourceURL: URL, displayName: String) async -> UUID? {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let id = UUID()
            let fileName = "\(id.uuidString).usdz"
            let destURL = rootURL.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.moveItem(at: sourceURL, to: destURL)
            cleanUpScanFolder(containing: sourceURL)
            let entry = Entry(
                id: id,
                displayName: Self.sanitizedName(displayName, fallbackDate: Date()),
                createdAt: Date(),
                fileName: fileName
            )
            entries.insert(entry, at: 0)
            try persistIndex()
            return id
        } catch {
            logger.error("failed to save capture: \(error.localizedDescription)")
            return nil
        }
    }

    func rename(id: UUID, to newName: String) throws {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].displayName = Self.sanitizedName(newName, fallbackDate: entries[idx].createdAt)
        try persistIndex()
    }

    func delete(id: UUID) throws {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let fileURL = rootURL.appendingPathComponent(entries[idx].fileName)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
        entries.remove(at: idx)
        try persistIndex()
    }

    func url(for id: UUID) -> URL? {
        guard let entry = entry(for: id) else { return nil }
        let candidate = rootURL.appendingPathComponent(entry.fileName)
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }

    func entry(for id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let formatted = formatter.string(from: date)
        return String(format: NSLocalizedString("model3d.captured.default_name_format", comment: ""), formatted)
    }

    private func persistIndex() throws {
        let data = try encoder.encode(entries)
        try data.write(to: indexURL, options: [.atomic])
    }

    private func cleanUpScanFolder(containing usdzURL: URL) {
        // sourceURL was at <tmp>/Scans/<timestamp>/model-mobile.usdz — drop the timestamped folder.
        let scanFolder = usdzURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: scanFolder)
    }

    private static func sanitizedName(_ raw: String, fallbackDate: Date) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultName(for: fallbackDate) }
        return String(trimmed.prefix(80))
    }
}

#endif
