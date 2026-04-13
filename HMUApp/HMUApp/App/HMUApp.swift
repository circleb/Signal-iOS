import SwiftUI
import AppAuth

@main
struct HMUApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authState = AuthStateManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authState)
        }
    }
}
