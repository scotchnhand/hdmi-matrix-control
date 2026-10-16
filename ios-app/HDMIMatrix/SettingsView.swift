import SwiftUI

/// Where the matrix lives and how to log in to it.
struct SettingsView: View {
    @Environment(ConnectionSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var demoMode = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Demo mode", isOn: $demoMode)
                } footer: {
                    Text("Uses a simulated matrix — no hardware needed.")
                }

                Section {
                    LabeledContent("Host") {
                        TextField("Host", text: $host, prompt: Text("matrix.local"))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.URL)
                    }
                    LabeledContent("Username") {
                        TextField("Username", text: $username)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Password") {
                        SecureField("Password", text: $password)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Matrix")
                } footer: {
                    Text("The app talks to the matrix directly over your local network. The default login is admin / admin.")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(demoMode)
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings.save(host: host, username: username, password: password, demoMode: demoMode)
                        dismiss()
                    }
                    .disabled(!demoMode && host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                host = settings.host
                username = settings.username
                password = settings.password
                demoMode = settings.demoMode
            }
        }
    }
}
