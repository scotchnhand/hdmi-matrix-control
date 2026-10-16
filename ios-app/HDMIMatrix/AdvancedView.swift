import MatrixKit
import SwiftUI

struct AdvancedView: View {
    @Environment(MatrixStore.self) private var store
    let device: MatrixState.Device

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
            Section("Device") {
                LabeledContent("IP address", value: device.ip.isEmpty ? "–" : device.ip)
                LabeledContent("Account", value: device.account.isEmpty ? "–" : device.account)
                LabeledContent("Firmware", value: device.firmware.isEmpty ? "–" : device.firmware)
            }

            Section {
                TextField("IP address", text: $ip, prompt: Text("192.168.1.168"))
                TextField("Subnet mask", text: $mask)
                TextField("Gateway", text: $gateway, prompt: Text("192.168.1.1"))
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
                TextField("Username", text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("New password", text: $newPassword)
                SecureField("Confirm password", text: $confirmPassword)
                Button("Change password") {
                    let (u, p) = (user, newPassword)
                    store.perform { try await $0.setCredentials(user: u, password: p) }
                    newPassword = ""
                    confirmPassword = ""
                }
                .disabled(!passwordValid)
            } header: {
                Text("Change device password")
            } footer: {
                Text("5–15 letters, numbers, or underscores. Update the app's connection settings afterwards.")
            }

            Section("Danger zone") {
                Button("Reboot matrix", role: .destructive) { confirming = .reboot }
                Button("Factory reset", role: .destructive) { confirming = .factoryReset }
            }
        }
        .navigationTitle("Advanced")
        .onAppear {
            if ip.isEmpty { ip = device.ip }
            if user.isEmpty { user = device.account }
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
        case .network: "The matrix will move to \(ip). Update the app's host setting to match."
        case .reboot: "Restarts the matrix. Takes about 15 seconds."
        case .factoryReset: "Erases all routing, names, EDID, and network settings."
        }
    }

    private func run(_ action: DangerAction) {
        switch action {
        case .network:
            let (i, m, g) = (ip, mask, gateway)
            store.perform { try await $0.setNetwork(ip: i, mask: m, gateway: g) }
        case .reboot:
            store.perform { try await $0.reboot() }
        case .factoryReset:
            store.perform { try await $0.factoryReset() }
        }
    }
}
