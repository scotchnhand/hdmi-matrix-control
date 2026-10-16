import MatrixKit
import SwiftUI

/// Connection settings, device info, and the rarely-needed admin actions.
/// Works without state, so you can fix the connection from here.
struct DeviceView: View {
    @Environment(MatrixStore.self) private var store
    @Environment(ConnectionSettings.self) private var settings
    @Binding var showingSettings: Bool

    private var device: MatrixState.Device? { store.state?.device }

    @State private var ip = ""
    @State private var mask = "255.255.255.0"
    @State private var gateway = ""
    @State private var user = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var confirming: DangerAction?

    enum DangerAction: Identifiable {
        case network, reboot, factoryReset
        var id: Self { self }
    }

    private var networkValid: Bool {
        [ip, mask, gateway].allSatisfy(Validation.isValidIPv4)
    }

    private var passwordValid: Bool {
        Validation.isValidCredential(user)
            && Validation.isValidCredential(newPassword)
            && newPassword == confirmPassword
    }

    var body: some View {
        Form {
            Section {
                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 14) {
                        Image("Artwork")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.demoMode ? "Demo matrix" : settings.host)
                                .font(.headline)
                            Text(settings.demoMode ? "Simulated — no hardware needed" : "Signed in as \(settings.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("connection-row")
            } header: {
                Text("Connection")
            }

            Section("Matrix") {
                LabeledContent("IP address", value: value(\.ip))
                LabeledContent("Account", value: value(\.account))
                LabeledContent("Firmware", value: value(\.firmware))
            }

            Section {
                LabeledContent("IP address") {
                    TextField("IP address", text: $ip, prompt: Text("192.168.1.168"))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Subnet mask") {
                    TextField("Subnet mask", text: $mask)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Gateway") {
                    TextField("Gateway", text: $gateway, prompt: Text("192.168.1.1"))
                        .multilineTextAlignment(.trailing)
                }
                Button("Apply network settings") { confirming = .network }
                    .disabled(!networkValid)
            } header: {
                Text("Network")
            } footer: {
                Text("Only change this if you know what you're doing — a wrong value can make the matrix unreachable until you factory-reset it.")
            }
            .keyboardType(.decimalPad)
            .autocorrectionDisabled()

            Section {
                LabeledContent("Username") {
                    TextField("Username", text: $user)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                LabeledContent("New password") {
                    SecureField("Required", text: $newPassword)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Confirm") {
                    SecureField("Required", text: $confirmPassword)
                        .multilineTextAlignment(.trailing)
                }
                Button("Change password") {
                    let (u, p) = (user, newPassword)
                    store.perform(onSuccess: {
                        // Keep the app's own login in step, or the next
                        // re-login (e.g. after a reboot) would fail.
                        if !settings.demoMode {
                            settings.save(host: settings.host, username: u, password: p, demoMode: false)
                        }
                    }) {
                        try await $0.setCredentials(user: u, password: p)
                    }
                    newPassword = ""
                    confirmPassword = ""
                }
                .disabled(!passwordValid)
            } header: {
                Text("Change device password")
            } footer: {
                Text("5–15 letters, numbers, or underscores. The app updates its own saved login to match.")
            }

            Section("Danger Zone") {
                Button("Reboot matrix", role: .destructive) { confirming = .reboot }
                Button("Factory reset", role: .destructive) { confirming = .factoryReset }
            }
        }
        .scrollContentBackground(.hidden)
        .background { MatrixBackdrop() }
        .onChange(of: device?.ip, initial: true) {
            if ip.isEmpty, let device { ip = device.ip }
            if user.isEmpty, let device { user = device.account }
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            Button(confirmLabel(action), role: .destructive) { run(action) }
        } message: { action in
            Text(confirmMessage(action))
        }
    }

    private func value(_ key: KeyPath<MatrixState.Device, String>) -> String {
        guard let text = device?[keyPath: key], !text.isEmpty else { return "–" }
        return text
    }

    private var dialogTitle: String {
        switch confirming {
        case .network: "Apply network settings?"
        case .reboot: "Reboot the matrix?"
        case .factoryReset: "Factory reset the matrix?"
        case nil: ""
        }
    }

    private func confirmLabel(_ action: DangerAction) -> String {
        switch action {
        case .network: "Apply"
        case .reboot: "Reboot"
        case .factoryReset: "Erase everything"
        }
    }

    private func confirmMessage(_ action: DangerAction) -> String {
        switch action {
        case .network: "The matrix will move to \(ip), and the app will reconnect to it there."
        case .reboot: "Restarts the matrix. Takes about 15 seconds."
        case .factoryReset: "Erases all routing, names, EDID, and network settings."
        }
    }

    private func run(_ action: DangerAction) {
        switch action {
        case .network:
            let (i, m, g) = (ip, mask, gateway)
            store.perform(expectOffline: .seconds(30), onSuccess: {
                // Follow the matrix to its new address.
                if !settings.demoMode {
                    settings.save(host: i, username: settings.username, password: settings.password, demoMode: false)
                }
            }) {
                try await $0.setNetwork(ip: i, mask: m, gateway: g)
            }
        case .reboot:
            store.reboot()
        case .factoryReset:
            store.factoryReset()
        }
    }
}
