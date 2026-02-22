import SwiftUI

struct PersonalDictionaryView: View {
    @EnvironmentObject var appState: AppState

    @State private var newOriginal = ""
    @State private var newReplacement = ""
    @State private var entries: [DictionaryEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // Add row
            Form {
                Section {
                    HStack(spacing: 8) {
                        TextField("Original word", text: $newOriginal)
                            .textFieldStyle(.roundedBorder)

                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)

                        TextField("Replacement", text: $newReplacement)
                            .textFieldStyle(.roundedBorder)

                        Button("Add") {
                            addEntry()
                        }
                        .disabled(newOriginal.isEmpty || newReplacement.isEmpty)
                    }
                } header: {
                    Text("Add Correction")
                } footer: {
                    Text("Words are matched case-insensitively. \"teh\" → \"the\" corrects transcription errors.")
                }
            }
            .formStyle(.grouped)

            Divider()

            // List
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No corrections yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Add word pairs above to auto-correct transcriptions.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.original)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(entry.replacement)
                                .fontWeight(.medium)
                            Spacer()
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            appState.removeDictionaryEntry(entries[i])
                        }
                    }
                }
            }
        }
        .task {
            entries = appState.dictionaryEntries
        }
        .onReceive(appState.$dictionaryEntries) { updated in
            entries = updated
        }
    }

    private func addEntry() {
        guard !newOriginal.isEmpty, !newReplacement.isEmpty else { return }
        appState.addDictionaryEntry(original: newOriginal, replacement: newReplacement)
        newOriginal = ""
        newReplacement = ""
    }
}

#Preview {
    PersonalDictionaryView()
        .environmentObject(AppState.shared)
        .frame(width: 550, height: 400)
}
