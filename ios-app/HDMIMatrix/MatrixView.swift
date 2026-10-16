import MatrixKit
import SwiftUI

struct RenameTarget: Identifiable {
    let kind: PortKind
    let index: Int
    let currentName: String
    var id: String { "\(kind.rawValue)\(index)" }
}

/// The main control surface: routing, audio, inputs/EDID, device info.
struct MatrixView: View {
    @Environment(MatrixStore.self) private var store
    let state: MatrixState
    @Binding var renameTarget: RenameTarget?

    var body: some View {
        List {
            Section {
                ForEach(state.outputs) { output in
                    OutputRouteCard(output: output, inputs: state.inputs) {
                        renameTarget = RenameTarget(kind: .output, index: output.index, currentName: output.name)
                    }
                }
            } header: {
                Text("Routing")
            } footer: {
                Text("Tap an input to send it to that output.")
            }

            Section("Audio") {
                AudioPicker(title: "ARC", selection: state.arc) { store.setAudio(.arc, $0) }
                AudioPicker(title: "Extraction", selection: state.extraction) { store.setAudio(.extraction, $0) }
            }

            Section("Inputs & EDID") {
                ForEach(state.inputs) { input in
                    InputRow(input: input) {
                        renameTarget = RenameTarget(kind: .input, index: input.index, currentName: input.name)
                    }
                }
            }

            Section {
                NavigationLink {
                    AdvancedView(device: state.device)
                } label: {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: state.outputs.map(\.inputIndex))
    }
}

struct OutputRouteCard: View {
    @Environment(MatrixStore.self) private var store
    let output: MatrixState.Output
    let inputs: [MatrixState.Input]
    let onRename: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(action: onRename) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(output.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Output \(output.index)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Rename this output")

                Spacer()

                Toggle(
                    "Power",
                    isOn: Binding(
                        get: { output.power },
                        set: { store.setPower(output: output.index, on: $0) }
                    )
                )
                .labelsHidden()
                .accessibilityLabel("\(output.name) power")
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(inputs) { input in
                    InputChip(
                        name: input.name,
                        isActive: input.index == output.inputIndex
                    ) {
                        guard input.index != output.inputIndex else { return }
                        store.route(output: output.index, to: input.index)
                    }
                    .disabled(!output.power)
                }
            }

            if !output.power {
                Text("Turn the output on to switch sources.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct InputChip: View {
    let name: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.body.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(isActive ? Color.accentForeground : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isActive ? Color.accentColor : Color(.tertiarySystemFill))
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct AudioPicker: View {
    let title: String
    let selection: AudioSource
    let onChange: (AudioSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            Picker(
                title,
                selection: Binding(get: { selection }, set: { if $0 != selection { onChange($0) } })
            ) {
                ForEach(AudioSource.allCases) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}

struct InputRow: View {
    @Environment(MatrixStore.self) private var store
    let input: MatrixState.Input
    let onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onRename) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(input.name).font(.body.weight(.semibold))
                        Text("Input \(input.index)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Rename this input")

                Spacer()

                Picker(
                    "EDID",
                    selection: Binding(
                        get: { input.edidPreset },
                        set: { store.setEDID(input: input.index, preset: $0) }
                    )
                ) {
                    ForEach(edidPresets.indices, id: \.self) { i in
                        Text(String(format: "%02d: %@", i, edidPresets[i])).tag(i)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("EDID preset for \(input.name)")
            }
            if !input.edidDetail.isEmpty {
                Text(input.edidDetail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(MatrixStore.preview())
        .environment(ConnectionSettings())
}
