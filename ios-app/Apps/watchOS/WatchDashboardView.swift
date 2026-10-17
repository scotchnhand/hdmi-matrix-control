import MatrixKit
import SwiftUI

struct WatchDashboardView: View {
    @StateObject private var session = WatchSessionCoordinator()
    @AppStorage("matrix-control-theme") private var themeRawValue = ThemePreference.system.rawValue

    var body: some View {
        NavigationStack {
            Group {
                if let state = session.state {
                    List {
                        Section("Connection") {
                            Label(
                                session.isReachable ? "iPhone connected" : "Open HDMI Matrix on iPhone",
                                systemImage: session.isReachable ? "iphone.gen3" : "iphone.slash"
                            )
                            .foregroundStyle(session.isReachable ? .green : .secondary)
                        }

                        Section("Outputs") {
                            ForEach(state.outputs) { output in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(output.name).font(.headline)
                                        Spacer()
                                        Button {
                                            session.setPower(output: output.index, on: !output.power)
                                        } label: {
                                            Image(systemName: output.power ? "power.circle.fill" : "power.circle")
                                                .foregroundStyle(output.power ? .green : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(output.name) power \(output.power ? "on" : "off")")
                                    }
                                    ForEach(state.inputs) { input in
                                        Button {
                                            session.route(output: output.index, input: input.index)
                                        } label: {
                                            HStack {
                                                Text(input.name)
                                                Spacer()
                                                if input.index == output.inputIndex {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.green)
                                                }
                                            }
                                        }
                                        .disabled(!output.power)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Open on iPhone",
                        systemImage: "iphone.and.arrow.forward",
                        description: Text("The iPhone app supplies the local network connection.")
                    )
                }
            }
            .navigationTitle("Matrix")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: session.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!session.isReachable)
                    .accessibilityLabel("Refresh matrix state")
                }
            }
            .overlay(alignment: .bottom) {
                if let error = session.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 8)
                }
            }
        }
        .preferredColorScheme(ThemePreference(rawValue: themeRawValue)?.colorScheme)
        .onAppear {
            session.activate()
            session.refresh()
        }
    }
}
