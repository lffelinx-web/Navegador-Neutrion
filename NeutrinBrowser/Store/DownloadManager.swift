import Foundation
import WebKit

/// Saves files from websites into the app's Documents folder ("Descargas"),
/// which shows up in the Files app under On My iPhone › Neutrin.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    struct Item: Identifiable, Equatable {
        enum State: Equatable { case downloading, finished, failed(String) }

        let id = UUID()
        var filename: String
        var fileURL: URL?
        var progress: Double = 0
        var state: State = .downloading
        let startedAt = Date()
    }

    @Published private(set) var items: [Item] = []
    /// The most recent download, shown briefly as a banner in the browser.
    @Published var latest: Item?

    private var itemIDs: [ObjectIdentifier: UUID] = [:]
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]

    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Descargas", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    override init() {
        super.init()
        loadExistingFiles()
    }

    func start(_ download: WKDownload) {
        download.delegate = self
    }

    func remove(_ item: Item) {
        if let url = item.fileURL { try? FileManager.default.removeItem(at: url) }
        items.removeAll { $0.id == item.id }
        if latest?.id == item.id { latest = nil }
    }

    /// Files downloaded earlier (they live in Documents/Descargas).
    private func loadExistingFiles() {
        let keys: [URLResourceKey] = [.creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: keys) else { return }
        items = urls
            .sorted { (date($0) ?? .distantPast) > (date($1) ?? .distantPast) }
            .map { Item(filename: $0.lastPathComponent, fileURL: $0, progress: 1, state: .finished) }
    }

    private func date(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    private func update(_ download: WKDownload, _ change: (inout Item) -> Void) {
        guard let id = itemIDs[ObjectIdentifier(download)], let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        if latest?.id == id { latest = items[index] }
    }

    /// "factura.pdf" → "factura 2.pdf" if the name is taken.
    private func uniqueURL(for filename: String) -> URL {
        let safeName = filename.replacingOccurrences(of: "/", with: "-")
        var url = Self.folder.appendingPathComponent(safeName.isEmpty ? "descarga" : safeName)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            url = Self.folder.appendingPathComponent(name)
            counter += 1
        }
        return url
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let destination = uniqueURL(for: suggestedFilename)
        var item = Item(filename: destination.lastPathComponent, fileURL: destination)
        item.state = .downloading
        items.insert(item, at: 0)
        itemIDs[ObjectIdentifier(download)] = item.id
        latest = item
        let id = item.id
        progressObservations[id] = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let value = progress.fractionCompleted
            Task { @MainActor in
                guard let self, let index = self.items.firstIndex(where: { $0.id == id }) else { return }
                self.items[index].progress = value
                if self.latest?.id == id { self.latest = self.items[index] }
            }
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        update(download) {
            $0.state = .finished
            $0.progress = 1
        }
        if let id = itemIDs.removeValue(forKey: ObjectIdentifier(download)) {
            progressObservations[id] = nil
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        update(download) { $0.state = .failed(error.localizedDescription) }
        if let id = itemIDs.removeValue(forKey: ObjectIdentifier(download)) {
            progressObservations[id] = nil
        }
    }
}
