import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authState: AuthStateManager
    @State private var showProfile = false
    @State private var showSignOutAlert = false

    var userInfo: SSOUserInfo? { authState.userInfo }

    var body: some View {
        NavigationStack {
            List {
                // Profile section
                Section {
                    HStack(spacing: 16) {
                        AvatarView(name: userInfo?.name ?? userInfo?.email)
                            .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(userInfo?.name ?? "Heritage Member")
                                .font(.headline)
                            if let email = userInfo?.email {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Roles & Groups
                if let roles = userInfo?.roles, !roles.isEmpty {
                    Section("Roles") {
                        ForEach(roles, id: \.self) { role in
                            Label(role, systemImage: "checkmark.seal.fill")
                                .foregroundColor(.hcpBlue)
                        }
                    }
                }

                // Quick links
                Section("Account") {
                    NavigationLink {
                        WebSheetView(
                            url: URL(string: "https://my.homesteadheritage.org/profile")!,
                            title: "HCP Profile"
                        )
                        .navigationBarHidden(true)
                    } label: {
                        Label("HCP Profile", systemImage: "person.crop.circle.fill")
                    }

                    NavigationLink {
                        WebSheetView(
                            url: URL(string: "https://my.homesteadheritage.org/feature-request")!,
                            title: "Feature Request"
                        )
                        .navigationBarHidden(true)
                    } label: {
                        Label("Feature Request", systemImage: "lightbulb.max")
                    }

                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("HMU Chat")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showProfile = true
                    } label: {
                        AvatarView(name: userInfo?.name ?? userInfo?.email)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .alert("Sign Out", isPresented: $showSignOutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) { authState.signOut() }
            } message: {
                Text("Are you sure you want to sign out of your Heritage account?")
            }
        }
    }
}
