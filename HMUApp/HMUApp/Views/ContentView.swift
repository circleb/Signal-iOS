import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authState: AuthStateManager

    var body: some View {
        if authState.isAuthenticated {
            HomeView()
        } else {
            LoginView()
        }
    }
}
