import SwiftUI

@main
struct NeutrinBrowserApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = BrowserStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.neutrinBlue)
        }
    }
}

/// The app stays in portrait; landscape is allowed only while a video plays fullscreen.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var allowedOrientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.allowedOrientations
    }
}
