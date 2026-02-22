import SwiftUI

// MARK: - Container

struct MeetingNotesView: View {
    let transcriptions: [Transcription]

    private var hourlyGroups: [(start: Date, items: [Transcription])] {
        let grouped = Dictionary(grouping: transcriptions) { t in
            Calendar.current.dateInterval(of: .hour, for: t.timestamp)?.start ?? t.timestamp
        }
        return grouped
            .map { (start: $0.key, items: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.start > $1.start }  // newest hour first
    }

    var body: some View {
        if hourlyGroups.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    AIStatusBanner()
                    ForEach(hourlyGroups, id: \.start) { group in
                        HourCard(hourStart: group.start, transcriptions: group.items)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.ambiAccent.opacity(0.1)).frame(width: 80, height: 80)
                Image(systemName: "note.text").font(.system(size: 32)).foregroundStyle(Color.ambiAccent)
            }
            VStack(spacing: 8) {
                Text("No notes yet").font(.headline)
                Text("Notes are grouped by hour.\nStart recording to see them here.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AI Status Banner

private struct AIStatusBanner: View {
    @ObservedObject private var llmManager = LocalLLMManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName).foregroundStyle(iconColor)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if case .error = llmManager.loadState {
                Button("Retry") { Task { await llmManager.loadModel() } }
                    .buttonStyle(.bordered).font(.caption)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var iconName: String {
        switch llmManager.loadState {
        case .ready:  return "cpu.fill"
        case .error:  return "exclamationmark.triangle"
        default:      return "cpu"
        }
    }

    private var iconColor: Color {
        switch llmManager.loadState {
        case .ready: return .green
        case .error: return .orange
        default:     return .secondary
        }
    }

    private var message: String {
        switch llmManager.loadState {
        case .idle:                return "\(llmManager.selectedModel.displayName) — tap Generate to summarize."
        case .downloading(let p):  return "Downloading \(llmManager.selectedModel.displayName)… \(Int(p * 100))%"
        case .loading:             return "Loading \(llmManager.selectedModel.displayName)…"
        case .ready:               return "\(llmManager.selectedModel.displayName) active — on-device AI."
        case .error(let e):        return "Error: \(e)"
        }
    }
}

// MARK: - Hour Card

struct HourCard: View {
    let hourStart: Date
    let transcriptions: [Transcription]

    @State private var bullets: [String] = []
    @State private var isGenerating = false

    private var storageKey: String {
        "hourNotes_\(Int(hourStart.timeIntervalSince1970))"
    }

    private var hourEnd: Date {
        Calendar.current.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart
    }

    private var timeRangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return "\(fmt.string(from: hourStart)) – \(fmt.string(from: hourEnd))"
    }

    private var category: MeetingCategory {
        let dominant = transcriptions.compactMap(\.sourceApp)
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key
        return MeetingCategory.from(sourceApp: dominant)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ambiAccent.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: category.sfSymbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.ambiAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeRangeLabel).font(.headline)
                    Text("\(transcriptions.count) segments · \(wordCount) words")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Body
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating notes…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if bullets.isEmpty {
                Button("Generate Notes") {
                    Task { await generate() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        Text(bullet).font(.body).lineSpacing(4).textSelection(.enabled)
                    }
                }

                Button {
                    Task { await generate() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
        .onAppear {
            if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
                bullets = saved
            }
        }
    }

    private var wordCount: Int {
        transcriptions.reduce(0) { count, t in
            count + t.text.split(separator: " ").count
        }
    }

    private func generate() async {
        isGenerating = true
        let text = transcriptions.map(\.text).joined(separator: " ")
        if let result = await LocalLLMManager.shared.summarize(text: text, category: category) {
            bullets = result
            UserDefaults.standard.set(result, forKey: storageKey)
        }
        isGenerating = false
    }
}
