import MatrixKit
import SwiftUI

/// Input names and EDID presets, one glass card per input.
struct InputsView: View {
    @Environment(MatrixStore.self) private var store
    let state: MatrixState
    @Binding var renameTarget: RenameTarget?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    ForEach(state.inputs) { input in
                        InputCard(input: input, routedTo: outputs(showing: input)) {
                            renameTarget = RenameTarget(kind: .input, index: input.index, currentName: input.name)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)

            Text("EDID tells each source what resolutions and audio formats to send. \"Copy Out-A/B\" mirrors whatever that display reports.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
    }

    private func outputs(showing input: MatrixState.Input) -> [MatrixState.Output] {
        state.outputs.filter { $0.power && $0.inputIndex == input.index }
    }
}

struct InputCard: View {
    @Environment(MatrixStore.self) private var store
    let input: MatrixState.Input
    let routedTo: [MatrixState.Output]
    let onRename: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Button(action: onRename) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(input.name).font(.title3.weight(.semibold))
                            Text("Input \(input.index)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Rename this input")
                    .accessibilityIdentifier("input-\(input.index)-name")

                    Spacer()

                    // Which screens this input is live on right now.
                    HStack(spacing: 6) {
                        ForEach(routedTo) { output in
                            Text(output.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .foregroundStyle(Color.accentForeground)
                                .background(Theme.color(forOutput: output.index).gradient, in: .capsule)
                        }
                    }
                }

                Menu {
                    Picker(
                        "EDID preset",
                        selection: Binding(
                            get: { input.edidPreset },
                            set: { store.setEDID(input: input.index, preset: $0) }
                        )
                    ) {
                        ForEach(edidPresets.indices, id: \.self) { i in
                            Text(String(format: "%02d  %@", i, edidPresets[i])).tag(i)
                        }
                    }
                } label: {
                    HStack {
                        Label(edidPresets[input.edidPreset], systemImage: "display")
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(.primary.opacity(0.1))
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("EDID preset for \(input.name): \(edidPresets[input.edidPreset])")
                .accessibilityIdentifier("input-\(input.index)-edid")

                if !input.edidDetail.isEmpty, input.edidDetail != edidPresets[input.edidPreset] {
                    Text(input.edidDetail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
        }
    }
}
