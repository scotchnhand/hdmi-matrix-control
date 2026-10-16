import MatrixKit
import SwiftUI

struct ContentView: View {
    @Environment(MatrixStore.self) private var store
    @Environment(ConnectionSettings.self) private var settings
    @State private var showingSettings = false
    @State private var renameTarget: RenameTarget?

    var body: some View {
        NavigationStack {
            Group {
                if let state = store.state {
                    MatrixView(state: state, renameTarget: $renameTarget)
                } else {
                    placeholder
                }
            }
            .navigationTitle("HDMI Matrix")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionBadge(connection: store.connection, demo: settings.demoMode)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $renameTarget) { target in
                RenameSheet(target: target)
            }
            .alert(
                "Couldn't do that",
                isPresented: Binding(
                    get: { store.errorMessage != nil },
                    set: { if !$0 { store.errorMessage = nil } }
                ),
                presenting: store.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch store.connection {
        case .lost(let message):
            ContentUnavailableView {
                Label("Can't reach the matrix", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
                Text("If it stays this way, power-cycle the matrix — its web server can lock up. No settings are lost.")
            } actions: {
                Button("Connection settings") { showingSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        default:
            ProgressView("Connecting to \(settings.demoMode ? "demo matrix" : settings.host)…")
        }
    }
}

struct ConnectionBadge: View {
    let connection: MatrixStore.Connection
    let demo: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch connection {
        case .connected: .green
        case .connecting: .orange
        case .lost: .red
        }
    }

    private var label: String {
        switch connection {
        case .connected: demo ? "Demo" : "Connected"
        case .connecting: "Connecting…"
        case .lost: "Connection lost"
        }
    }
}

#Preview {
    ContentView()
        .environment(MatrixStore.preview())
        .environment(ConnectionSettings())
}
