import SwiftUI
import QuickLook

/// Matches from favorites and history while typing an address, plus a "search" row.
struct SuggestionsList: View {
    @EnvironmentObject private var store: BrowserStore
    let query: String
    let onOpen: (URL) -> Void
    let onSearch: () -> Void

    var body: some View {
        let matches = store.suggestions(for: query)
        VStack(spacing: 0) {
            Button(action: onSearch) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 30, height: 30)
                        .background(Color.neutrinBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(Color.neutrinBlue)
                    Text("Buscar «\(query)»")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(store.searchEngine.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(matches) { entry in
                Divider().padding(.leading, 56)
                Button { onOpen(entry.url) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: store.isFavorite(entry.url) ? "star.fill" : "clock")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(store.isFavorite(entry.url) ? Color.orange : Color.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.displayTitle)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(entry.url.displayHost)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .glass(cornerRadius: 22)
    }
}

/// Small banner while a file downloads; tap to see all downloads.
struct DownloadBanner: View {
    @ObservedObject var downloads: DownloadManager
    let onOpenList: () -> Void

    var body: some View {
        if let item = downloads.latest {
            Button(action: onOpenList) {
                HStack(spacing: 10) {
                    Group {
                        switch item.state {
                        case .downloading:
                            ProgressView(value: item.progress).progressViewStyle(.circular).controlSize(.small)
                        case .finished:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                    .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.filename).font(.footnote.weight(.semibold)).lineLimit(1)
                        Text(statusText(item)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        downloads.latest = nil
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Cerrar aviso")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glass(cornerRadius: 20)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: item.state) {
                // Hide a few seconds after it finishes.
                guard item.state != .downloading else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if downloads.latest?.id == item.id { withAnimation { downloads.latest = nil } }
            }
        }
    }

    private func statusText(_ item: DownloadManager.Item) -> String {
        switch item.state {
        case .downloading: "Descargando… \(Int(item.progress * 100)) %"
        case .finished: "Guardado en Archivos › Neutrin › Descargas"
        case .failed(let reason): "No se pudo descargar: \(reason)"
        }
    }
}

/// All downloads, with Quick Look preview and sharing.
struct DownloadsView: View {
    @ObservedObject var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            List {
                ForEach(downloads.items) { item in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: item))
                            .font(.title3)
                            .foregroundStyle(Color.neutrinBlue)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.filename).font(.subheadline.weight(.medium)).lineLimit(2)
                            switch item.state {
                            case .downloading:
                                ProgressView(value: item.progress)
                            case .finished:
                                Text(item.startedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption).foregroundStyle(.secondary)
                            case .failed(let reason):
                                Text(reason).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                        if item.state == .finished, let url = item.fileURL {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.borderless)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if item.state == .finished { previewURL = item.fileURL }
                    }
                }
                .onDelete { offsets in
                    offsets.map { downloads.items[$0] }.forEach(downloads.remove)
                }
            }
            .overlay {
                if downloads.items.isEmpty {
                    ContentUnavailableView("Sin descargas", systemImage: "arrow.down.circle",
                                           description: Text("Los archivos que descargues aparecerán aquí y en la app Archivos."))
                }
            }
            .navigationTitle("Descargas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .quickLookPreview($previewURL)
        }
    }

    private func icon(for item: DownloadManager.Item) -> String {
        switch item.fileURL?.pathExtension.lowercased() ?? "" {
        case "pdf": "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": "photo"
        case "mp4", "mov", "m4v": "film"
        case "mp3", "m4a", "wav": "music.note"
        case "zip", "rar", "7z": "doc.zipper"
        default: "doc"
        }
    }
}
