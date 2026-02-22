import SwiftUI

// MARK: - Container

struct MeetingNotesView: View {
    let transcriptions: [Transcription]
    let summarizer: MeetingSummarizer

    @AppStorage("summarizationMode") private var storedMode = SummarizationMode.localLLM.rawValue
    private var mode: SummarizationMode { SummarizationMode(rawValue: storedMode) ?? .localLLM }

    private var meetings: [Meeting] { MeetingSegmenter.segment(transcriptions) }

    var body: some View {
        if meetings.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    AIStatusBanner(mode: mode)
                    ForEach(meetings) { meeting in
                        MeetingCard(meeting: meeting, mode: mode, summarizer: summarizer)
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
                Text("No meetings yet").font(.headline)
                Text("Notes will be grouped into meetings\nonce transcriptions accumulate.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - AI Status Banner

private struct AIStatusBanner: View {
    let mode: SummarizationMode
    @ObservedObject private var llmManager = LocalLLMManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: llmManager.loadState.isReady ? "cpu.fill" : "cpu")
                .foregroundStyle(llmManager.loadState.isReady ? Color.green : Color.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(llmManager.loadState.isReady ? Color.secondary : Color.orange)
            Spacer()

            if llmManager.loadState == .idle {
                Button("Load Model") {
                    Task { await llmManager.loadModel() }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var message: String {
        switch llmManager.loadState {
        case .idle:
            return "\(llmManager.selectedModel.displayName) not downloaded yet."
        case .downloading(let p):
            return "Downloading \(llmManager.selectedModel.displayName)… \(Int(p * 100))%"
        case .loading:
            return "Loading \(llmManager.selectedModel.displayName)…"
        case .ready:
            return "\(llmManager.selectedModel.displayName) active — on-device AI summarization."
        case .error(let e):
            return "Model error: \(e)"
        }
    }
}

// MARK: - Meeting Card

struct MeetingCard: View {
    let meeting: Meeting
    let mode: SummarizationMode
    let summarizer: MeetingSummarizer

    @State private var bullets: [String] = []
    @State private var isLoading = true
    @ObservedObject private var llmManager = LocalLLMManager.shared

    private var timeLabel: String {
        meeting.startTime.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ambiAccent.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: meeting.category.sfSymbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.ambiAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title).font(.headline)
                    Text("\(timeLabel)  ·  \(meeting.formattedDuration)  ·  \(meeting.transcriptions.count) segments")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                if let app = meeting.dominantApp {
                    Text(app)
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }

            Divider()

            // ── Summary ─────────────────────────────────────────────
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating notes…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if bullets.isEmpty {
                Text("Nothing to summarize.").font(.caption).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        Text(bullet).font(.body).lineSpacing(4).textSelection(.enabled)
                    }
                }
            }

            // ── Footer ───────────────────────────────────────────────
            HStack {
                Button {
                    Task { await doRegenerate() }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)

                Spacer()

                Text("Local AI")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
        .task(id: llmManager.loadState.isReady) {
            await doLoad()
        }
    }

    private func doLoad() async {
        isLoading = true
        bullets = await summarizer.summarize(meeting: meeting, mode: mode)
        isLoading = false
    }

    private func doRegenerate() async {
        isLoading = true
        bullets = await summarizer.regenerate(meeting: meeting, mode: mode)
        isLoading = false
    }
}
