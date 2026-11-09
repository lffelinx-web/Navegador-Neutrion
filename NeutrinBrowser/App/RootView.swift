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
        // Tabs & Spaces slides up over the page and can be swiped down to close.
        .overlay {
            if showTabs {
                TabsSpacesView { withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { showTabs = false } }
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: showTabs)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.checkForFilterListUpdates()
                store.updateSystemAppearance(isDark: Self.systemIsDark)
            } else {
                store.save()
            }
        }
        // Read the phone's real appearance: the browser may tint its own window
        // to match a dark or light page, which also changes `colorScheme`.
        .onAppear { store.updateSystemAppearance(isDark: Self.systemIsDark) }
        .onChange(of: colorScheme) { _, _ in store.updateSystemAppearance(isDark: Self.systemIsDark) }
    }

    private static var systemIsDark: Bool {
        UIScreen.main.traitCollection.userInterfaceStyle == .dark
    }
}
