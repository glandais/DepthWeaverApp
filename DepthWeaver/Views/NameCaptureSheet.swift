import SwiftUI

struct NameCaptureSheet: View {
    let title: LocalizedStringKey
    let initialName: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(
        title: LocalizedStringKey = "model3d.captured.name_prompt_title",
        initialName: String,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.initialName = initialName
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("model3d.captured.name_field_label", text: $name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitSave() }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("general.cancel", role: .cancel) { onCancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("general.save") { commitSave() }
                        .bold()
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium])
    }

    private func commitSave() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? initialName : trimmed)
    }
}
