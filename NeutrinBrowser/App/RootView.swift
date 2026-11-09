import SwiftUI

/// Shows the start page for an empty tab, or the web page for a loaded one.
struct RootView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTabs = false

    var body: some View {
        ZStack {
            AppBackground()

            if let tab = store.activeTab, tab.url != nil {
                BrowserView(controller: store.controller(for: tab.id), showTabs: $showTabs)
                    .id(tab.id)
                    .transition(.opacity)
            } else {
                HomeView(showTabs: $showTabs)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.activeTab?.url == nil)
        // A sheet so it can be closed by swiping down.
        .sheet(isPresented: $showTabs) {
            TabsSpacesView()
                .environmentObject(store)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.checkForFilterListUpdates()
            } else {
                store.save()
            }
        }
        .onAppear { store.updateSystemAppearance(isDark: colorScheme == .dark) }
        .onChange(of: colorScheme) { _, scheme in
            store.updateSystemAppearance(isDark: scheme == .dark)
        }
    }
}
