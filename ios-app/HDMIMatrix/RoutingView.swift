import MatrixKit
import SwiftUI

struct RenameTarget: Identifiable {
    let kind: PortKind
    let index: Int
    let currentName: String
    var id: String { "\(kind.rawValue)\(index)" }
}

/// The main control surface: one glass card per output, then audio.
struct RoutingView: View {
    @Environment(MatrixStore.self) private var store
    let state: MatrixState
    @Binding var renameTarget: RenameTarget?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    ForEach(state.outputs) { output in
                        OutputCard(output: output, inputs: state.inputs) {
                            renameTarget = RenameTarget(kind: .output, index: output.index, currentName: output.name)
                        }
                    }
                    AudioCard(state: state)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .sensoryFeedback(.selection, trigger: state.outputs.map(\.inputIndex))
    }
}

struct OutputCard: View {
    @Environment(MatrixStore.self) private var store
    let output: MatrixState.Output
    let inputs: [MatrixState.Input]
    let onRename: () -> Void

    @Namespace private var selection
    private var color: Color { Theme.color(forOutput: output.index) }
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        GlassCard(tint: output.power ? color : nil) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: output.power ? "tv.fill" : "tv")
                        .font(.title2)
                        .foregroundStyle(output.power ? color : .secondary)
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))

                    Button(action: onRename) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(output.name)
                                .font(.title3.weight(.semibold))
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
                            set: { on in withAnimation(.smooth) { store.setPower(output: output.index, on: on) } }
                        )
                    )
                    .labelsHidden()
                    .tint(color)
                    .accessibilityLabel("\(output.name) power")
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(inputs) { input in
                        chip(for: input)
                    }
                }
                .disabled(!output.power)

                if !output.power {
                    Label("Turn the output on to switch sources.", systemImage: "power")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chip(for input: MatrixState.Input) -> some View {
        let isActive = input.index == output.inputIndex
        return Button {
            guard !isActive else { return }
            withAnimation(.bouncy(duration: 0.4)) {
                store.route(output: output.index, to: input.index)
            }
        } label: {
            Text(input.name)
                .font(.body.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(isActive ? Color.accentForeground : .primary)
                .background {
                    // The selected pill slides between chips, like a drop of
                    // liquid following your finger.
                    if isActive {
                        Capsule()
                            .fill(color.gradient)
                            .shadow(color: color.opacity(output.power ? 0.6 : 0), radius: 10)
                            .matchedGeometryEffect(id: "selected", in: selection)
                    } else {
                        Capsule()
                            .fill(.primary.opacity(0.1))
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .opacity(output.power || isActive ? 1 : 0.5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route \(input.name) to \(output.name)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct AudioCard: View {
    @Environment(MatrixStore.self) private var store
    let state: MatrixState

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Audio", systemImage: "speaker.wave.2.fill")
                    .font(.headline)
                AudioPicker(title: "ARC", selection: state.arc) { store.setAudio(.arc, $0) }
                AudioPicker(title: "Extraction", selection: state.extraction) { store.setAudio(.extraction, $0) }
            }
        }
    }
}

struct AudioPicker: View {
    let title: String
    let selection: AudioSource
    let onChange: (AudioSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
    }
}

#Preview {
    ContentView()
        .environment(MatrixStore.preview())
        .environment(ConnectionSettings())
}
