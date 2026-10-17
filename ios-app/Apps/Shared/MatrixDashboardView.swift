import Foundation
import MatrixKit
import SwiftUI

struct MatrixDashboardView: View {
    @ObservedObject var model: MatrixDashboardModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    connectionCard

                    if let errorMessage = model.errorMessage {
                        errorCard(errorMessage)
                    }

                    if let state = model.state {
                        routingCard(state)
                        audioCard(state)
                        inputsCard(state)
                        deviceCard(state)
                    } else if !model.isLoading {
                        ContentUnavailableView(
                            "Connect to your matrix",
                            systemImage: "rectangle.connected.to.line.below",
                            description: Text("Enter the local web-app address above to load routing controls.")
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("HDMI Matrix")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Appearance", selection: $model.theme) {
                            ForEach(ThemePreference.allCases) { preference in
                                Label(preference.label, systemImage: icon(for: preference))
                                    .tag(preference)
                            }
                        }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                    .accessibilityLabel("Appearance")
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: model.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                    .accessibilityLabel("Refresh matrix state")
                }
            }
        }
        .preferredColorScheme(model.theme.colorScheme)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Control service", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating matrix state")
                } else {
                    Label(model.isConnected ? "Connected" : "Not connected", systemImage: model.isConnected ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.isConnected ? .green : .secondary)
                }
            }
            TextField("http://matrix-host:8765", text: $model.baseURLText)
#if !os(tvOS)
                .textFieldStyle(.roundedBorder)
#endif
#if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
#endif
            HStack {
                Button(model.isConnected ? "Reconnect" : "Connect", action: model.connect)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoading)
                if let lastUpdatedAt = model.lastUpdatedAt {
                    Text("Updated \(lastUpdatedAt, format: .dateTime.hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Label {
                Text(message)
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "wifi.exclamationmark")
            }
            .font(.callout)
            .foregroundStyle(.red)
            Spacer(minLength: 0)
            Button("Retry", action: model.refresh)
                .buttonStyle(.bordered)
                .disabled(model.isLoading)
        }
        .padding()
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func routingCard(_ state: MatrixState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Routing", systemImage: "rectangle.split.2x1")
                .font(.headline)

            ForEach(state.outputs) { output in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(output.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Toggle("Power", isOn: Binding(
                            get: { output.power },
                            set: { model.setOutputPower(output: output.index, on: $0) }
                        ))
                        .labelsHidden()
                        .accessibilityLabel("\(output.name) power")
                        Text(output.power ? "On" : "Off")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(output.power ? .green : .secondary)
                    }

                    Picker("Source for \(output.name)", selection: Binding(
                        get: { output.inputIndex },
                        set: { model.setRoute(output: output.index, input: $0) }
                    )) {
                        ForEach(state.inputs) { input in
                            Text(input.name).tag(input.index)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!output.power)
                }
                .padding()
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func audioCard(_ state: MatrixState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Audio", systemImage: "hifispeaker.2")
                .font(.headline)
            audioPicker(title: "ARC", mode: "arc", value: state.audio.arc.value)
            audioPicker(title: "Extraction", mode: "extraction", value: state.audio.extraction.value)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func audioPicker(title: String, mode: String, value: Int) -> some View {
        Picker(title, selection: Binding(
            get: { value },
            set: { model.setAudio(mode: mode, value: $0) }
        )) {
            Text("Off").tag(0)
            Text("Out-A").tag(1)
            Text("Out-B").tag(2)
        }
        .pickerStyle(.segmented)
    }

    private func inputsCard(_ state: MatrixState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Inputs & EDID", systemImage: "rectangle.connected.to.line.below")
                .font(.headline)

            ForEach(state.inputs) { input in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(input.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Input \(input.index)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("EDID preset for \(input.name)", selection: Binding(
                        get: { input.edidPreset },
                        set: { model.setEDID(input: input.index, preset: $0) }
                    )) {
                        ForEach(state.edidPresets) { preset in
                            Text("\(String(format: "%02d", preset.index)): \(preset.name)")
                                .tag(preset.index)
                        }
                    }
                    .pickerStyle(.menu)

                    if !input.edidDetail.isEmpty {
                        Text(input.edidDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func deviceCard(_ state: MatrixState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Device", systemImage: "info.circle")
                .font(.headline)
            LabeledContent("Address", value: state.device.ip.isEmpty ? "—" : state.device.ip)
            LabeledContent("Account", value: state.device.account.isEmpty ? "—" : state.device.account)
            LabeledContent("Firmware", value: state.device.firmware.isEmpty ? "—" : state.device.firmware)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func icon(for preference: ThemePreference) -> String {
        switch preference {
        case .system: return "gearshape"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}
