import MatrixKit
import SwiftUI

struct RenameSheet: View {
    @Environment(MatrixStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: RenameTarget
    @State private var name: String

    init(target: RenameTarget) {
        self.target = target
        _name = State(initialValue: target.currentName)
    }

    private var isValid: Bool { Validation.isValidPortName(name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    Text("3–15 letters, numbers, or underscores.")
                        .foregroundStyle(isValid || name.isEmpty ? Color.secondary : Color.red)
                }
            }
            .navigationTitle("Rename \(target.kind == .input ? "Input" : "Output") \(target.index)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard isValid else { return }
        if name != target.currentName {
            store.rename(target.kind, index: target.index, to: name)
        }
        dismiss()
    }
}
