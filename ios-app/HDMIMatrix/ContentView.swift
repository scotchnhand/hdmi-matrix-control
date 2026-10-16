import MatrixKit
import SwiftUI

struct ContentView: View {
    @Environment(MatrixStore.self) private var store
    @State private var renameTarget: RenameTarget?
    @State private var showingSettings = false

    var body: some View {
        TabView {
            Tab("Routing", systemImage: "arrow.triangle.branch") {
                NavigationStack {
                    StateGate(showingSettings: $showingSettings) { state in
                        RoutingView(state: state, renameTarget: $renameTarget)
                    }
                    .navigationTitle("Routing")
                }
            }
            Tab("Inputs", systemImage: "cable.connector.horizontal") {
                NavigationStack {
                    StateGate(showingSettings: $showingSettings) { state in
                        InputsView(state: state, renameTarget: $renameTarget)
                    }
                    .navigationTitle("Inputs")
                }
            }
            Tab("Device", systemImage: "gearshape") {
                NavigationStack {
                    DeviceView(showingSettings: $showingSettings)
                        .navigationTitle("Device")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            ConnectionAccessory()
        }
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

/// Shows its content once there's state, and a connecting / unreachable
/// screen until then.
struct StateGate<Content: View>: View {
    @Environment(MatrixStore.self) private var store
    @Environment(ConnectionSettings.self) private var settings
    @Binding var showingSettings: Bool
    @ViewBuilder var content: (MatrixState) -> Content

    var body: some View {
        ZStack {
            MatrixBackdrop()
            if let state = store.state {
                content(state)
            } else {
                placeholder
            }
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch store.connection {
        case .lost(let message):
            ContentUnavailableView {
                Label {
                    Text("Can't reach the matrix")
                } icon: {
                    Image("Artwork").resizable().scaledToFit().frame(width: 120)
                }
            } description: {
                Text(message)
                Text("If it stays this way, power-cycle the matrix — its web server can lock up. No settings are lost.")
            } actions: {
                Button("Connection Settings") { showingSettings = true }
                    .buttonStyle(.glassProminent)
            }
        default:
            VStack(spacing: 20) {
                Image("Artwork")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140)
                    .phaseAnimator([1.0, 0.55]) { view, opacity in
                        view.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.9) }
                Text("Connecting to \(settings.demoMode ? "the demo matrix" : settings.host)…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Lives above the tab bar: connection status at a glance, plus retry.
struct ConnectionAccessory: View {
    @Environment(MatrixStore.self) private var store
    @Environment(ConnectionSettings.self) private var settings
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(label)
                .font(.subheadline.weight(.semibold))
            if placement != .inline {
                Text(settings.demoMode ? "Demo matrix" : settings.host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if case .lost = store.connection {
                Button("Retry", systemImage: "arrow.clockwise") {
                    Task { await store.refresh() }
                }
                .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch store.connection {
        case .connected: .green
        case .connecting: .orange
        case .lost: .red
        }
    }

    private var label: String {
        switch store.connection {
        case .connected: "Connected"
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
