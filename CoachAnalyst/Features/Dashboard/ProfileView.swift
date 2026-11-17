import SwiftUI

struct ProfileView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(ScoutingStore.self) private var scouting

    @State private var backendURL = UserDefaults.standard.string(forKey: BackendConfig.defaultsKey) ?? ""
    @State private var savedConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                if let user = auth.currentUser {
                    Section {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name).font(.headline)
                                Text(user.email).font(.caption).foregroundStyle(.secondary)
                                Text(user.role).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Integrations") {
                    ForEach(DataSource.allCases) { source in
                        HStack {
                            Image(systemName: source.symbol).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName)
                                Text(source.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Label("Active backend", systemImage: "server.rack")
                        Spacer()
                        Text(scouting.backendLabel).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Data Backend")
                } footer: {
                    Text("Leave empty to compute on-device. Enter the BFF base URL (e.g. http://127.0.0.1:8000) to offload data and similarity. Applies on next launch.")
                }

                Section {
                    TextField("BFF base URL", text: $backendURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save backend URL") {
                        let trimmed = backendURL.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            UserDefaults.standard.removeObject(forKey: BackendConfig.defaultsKey)
                        } else {
                            UserDefaults.standard.set(trimmed, forKey: BackendConfig.defaultsKey)
                        }
                        savedConfirmation = true
                    }
                    if savedConfirmation {
                        Text("Saved. Relaunch the app to switch backends.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        auth.signOut()
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
        .environment(AuthStore())
        .environment(ScoutingStore())
}
