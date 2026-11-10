import SwiftUI
import LocalAuthentication

/// Pages saved to read later (Inicio › Leer, or ⋯ › Añadir a lista de lectura).
struct ReadingListView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    let onOpen: (URL) -> Void
    @State private var showRead = false

    private var items: [ReadingItem] {
        store.readingList.filter { showRead || !$0.isRead }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    Button {
                        store.markRead(item)
                        onOpen(item.url)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.isRead ? "book.closed" : "book")
                                .foregroundStyle(item.isRead ? Color.secondary : Color.neutrinBlue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayTitle)
                                    .font(.subheadline.weight(item.isRead ? .regular : .semibold))
                                    .lineLimit(2)
                                Text(item.url.displayHost)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button(item.isRead ? "No leído" : "Leído") { store.markRead(item, !item.isRead) }
                            .tint(Color.neutrinBlue)
                    }
                }
                .onDelete { store.removeReadingItems(at: $0, in: items) }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Lista de lectura vacía", systemImage: "book",
                                           description: Text("Guarda artículos desde ⋯ › Añadir a lista de lectura para leerlos después."))
                }
            }
            .navigationTitle("Lista de lectura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Listo") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(showRead ? "Ocultar leídos" : "Mostrar leídos") { showRead.toggle() }
                }
            }
        }
    }
}

/// Sites you visit most (Inicio › Frecuentes).
struct TopSitesView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    let onOpen: (URL) -> Void

    var body: some View {
        NavigationStack {
            let sites = store.topSites()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 14)], spacing: 18) {
                    ForEach(sites) { site in
                        Button { onOpen(site.url) } label: {
                            VStack(spacing: 8) {
                                Text(String(site.url.displayHost.prefix(1)).uppercased())
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(width: 60, height: 60)
                                    .background(LinearGradient.neutrin, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                Text(site.url.displayHost)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: 90)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .overlay {
                if sites.isEmpty {
                    ContentUnavailableView("Aún no hay sitios frecuentes", systemImage: "chart.bar",
                                           description: Text("Los sitios que más visites aparecerán aquí."))
                }
            }
            .navigationTitle("Frecuentes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Inicio › Herramientas.
struct ToolsView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Tool) -> Void

    enum Tool: CaseIterable, Identifiable {
        case downloads, history, readingList, scanner, privateTab, settings
        var id: Self { self }

        var title: String {
            switch self {
            case .downloads: "Descargas"
            case .history: "Historial"
            case .readingList: "Lista de lectura"
            case .scanner: "Escanear QR"
            case .privateTab: "Pestaña privada"
            case .settings: "Ajustes"
            }
        }

        var symbol: String {
            switch self {
            case .downloads: "arrow.down.circle"
            case .history: "clock"
            case .readingList: "book"
            case .scanner: "qrcode.viewfinder"
            case .privateTab: "eye.slash"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 16) {
                ForEach(Tool.allCases) { tool in
                    Button { onSelect(tool) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 22))
                                .foregroundStyle(Color.neutrinBlue)
                                .frame(width: 56, height: 56)
                                .card(cornerRadius: 17)
                            Text(tool.title)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AppBackground())
            .navigationTitle("Herramientas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// Covers private tabs until Face ID / passcode unlocks them.
struct PrivateLockView: View {
    @EnvironmentObject private var store: BrowserStore
    @State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(Color.indigo, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text("Pestañas privadas bloqueadas")
                .font(.title3.weight(.bold))
            Text("Usa Face ID o tu código para verlas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                unlock()
            } label: {
                Label("Desbloquear", systemImage: "faceid")
                    .font(.headline)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(Color.indigo, in: Capsule())
                    .foregroundStyle(.white)
            }
            if failed {
                Text("No se pudo verificar. Inténtalo de nuevo.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button("Ir a mis pestañas normales") {
                store.selectSpace(store.activeSpaceID)
            }
            .font(.subheadline)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task { unlock() }
    }

    private func unlock() {
        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on the phone: nothing to protect with.
            store.privateTabsLocked = false
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Desbloquear tus pestañas privadas") { success, _ in
            Task { @MainActor in
                if success {
                    store.privateTabsLocked = false
                    failed = false
                } else {
                    failed = true
                }
            }
        }
    }
}
