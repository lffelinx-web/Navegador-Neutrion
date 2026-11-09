import SwiftUI

@main
struct NeutrinBrowserApp: App {
    @StateObject private var store = BrowserStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.neutrinBlue)
        }
    }
}
