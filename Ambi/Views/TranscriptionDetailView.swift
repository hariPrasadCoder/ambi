import SwiftUI

// MARK: - View mode

enum SessionViewMode: String, CaseIterable {
    case timeline = "Timeline"
    case notes    = "Notes"
}

// MARK: - Main view

struct TranscriptionDetailView: View {
    @EnvironmentObject var appState: AppState
    let session: Session

    @State private var hoveredId: Int64?
    @State private var viewMode: SessionViewMode = .timeline

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(session: session, viewMode: $viewMode)
            Divider()

            switch viewMode {
            case .timeline:
                timelineContent
            case .notes:
                MeetingNotesView(
                    transcriptions: appState.transcriptions,
                    summarizer: AppState.shared.meetingSummarizer
                )
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Timeline

    private var timelineContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    if appState.transcriptions.isEmpty && !appState.isRecording {
                        EmptyTranscriptionView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                    } else {
                        ForEach(appState.transcriptions.reversed()) { transcription in
                            TranscriptionBlock(
                                transcription: transcription,
                                isHovered: hoveredId == transcription.id
                            )
                            .onHover { isHovered in
                                hoveredId = isHovered ? transcription.id : nil
                            }
                            .id(transcription.id)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: appState.transcriptions.count) { _ in
                if let latestId = appState.transcriptions.last?.id {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(latestId, anchor: .top)
                    }
                }
            }
        }
    }

    private var isCurrentSession: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let sessionDay = Calendar.current.startOfDay(for: session.date)
        return today == sessionDay
    }
}

// MARK: - Detail Header

struct DetailHeader: View {
    @EnvironmentObject var appState: AppState
    let session: Session
    @Binding var viewMode: SessionViewMode

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 12) {
                    Label(session.formattedDate, systemImage: "calendar")
                    Label(session.timeString, systemImage: "clock")

                    if !appState.transcriptions.isEmpty {
                        Label("\(appState.transcriptions.count) segments", systemImage: "text.alignleft")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // View mode toggle
            Picker("", selection: $viewMode) {
                ForEach(SessionViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            HStack(spacing: 8) {
                Button(action: copyAll) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(HeaderButtonStyle())
                .help("Copy all transcriptions")
                
                Button(action: exportSession) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(HeaderButtonStyle())
                .help("Export session")
                
                Menu {
                    Button(action: copyAll) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: exportSession) {
                        Label("Export as Text", systemImage: "doc.text")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        appState.deleteSession(session)
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 32, height: 32)
            }
        }
        .padding()
    }
    
    private func copyAll() {
        let text = appState.transcriptions.map { $0.text }.joined(separator: "\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func exportSession() {
        let text = appState.transcriptions.map { "[\($0.formattedTime)] \($0.text)" }.joined(separator: "\n\n")
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(session.displayTitle).txt"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear)
            )
            .foregroundStyle(.secondary)
    }
}


// MARK: - Transcription Block

struct TranscriptionBlock: View {
    let transcription: Transcription
    let isHovered: Bool

    @State private var isCopied = false
    @State private var processedText: String? = nil
    @State private var isCopiedProcessed = false
    private let processor = TextProcessor()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timestamp
            Text(transcription.formattedTime)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)

            // Timeline indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.ambiAccent)
                    .frame(width: 8, height: 8)

                Rectangle()
                    .fill(Color.ambiAccent.opacity(0.3))
                    .frame(width: 2)
            }

            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(transcription.text)
                    .font(.body)
                    .lineSpacing(6)
                    .textSelection(.enabled)

                // Source app badge
                if let appName = transcription.sourceApp {
                    HStack(spacing: 4) {
                        Image(systemName: sfSymbol(for: appName))
                        Text(appName)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }

                // Processed text display
                if let processed = processedText {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(processed)
                            .font(.body)
                            .lineSpacing(6)
                            .foregroundStyle(.primary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.ambiAccent.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.ambiAccent.opacity(0.2), lineWidth: 1)
                                    )
                            )

                        HStack(spacing: 8) {
                            Button(action: copyProcessed) {
                                Label(isCopiedProcessed ? "Copied" : "Copy Processed",
                                      systemImage: isCopiedProcessed ? "checkmark" : "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)

                            Button("Dismiss") {
                                withAnimation { processedText = nil }
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Hover action buttons
                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: copyText) {
                            Label(isCopied ? "Copied" : "Copy",
                                  systemImage: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Button("Clean Up") { applyProcessing(.cleanUp) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Bullets") { applyProcessing(.formatAsBullets) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.primary.opacity(0.03) : Color.clear)
            )
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onChange(of: isHovered) { hovered in
            if !hovered { processedText = nil }
        }
    }

    private func applyProcessing(_ type: TextProcessor.ProcessingType) {
        let result = processor.process(transcription.text, type: type)
        withAnimation { processedText = result }
    }

    private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcription.text, forType: .string)
        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isCopied = false }
        }
    }

    private func copyProcessed() {
        guard let text = processedText else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        withAnimation { isCopiedProcessed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isCopiedProcessed = false }
        }
    }

    private func sfSymbol(for appName: String) -> String {
        let name = appName.lowercased()
        if name.contains("safari") { return "safari" }
        if name.contains("chrome") || name.contains("firefox") || name.contains("arc") { return "globe" }
        if name.contains("mail") { return "envelope" }
        if name.contains("slack") || name.contains("discord") { return "message" }
        if name.contains("zoom") || name.contains("meet") || name.contains("teams") { return "video" }
        if name.contains("code") || name.contains("xcode") || name.contains("cursor") { return "curlybraces" }
        if name.contains("terminal") || name.contains("iterm") { return "terminal" }
        if name.contains("notes") || name.contains("notion") || name.contains("obsidian") { return "note.text" }
        if name.contains("music") || name.contains("spotify") { return "music.note" }
        if name.contains("finder") { return "folder" }
        if name.contains("word") || name.contains("pages") || name.contains("docs") { return "doc.text" }
        return "app.fill"
    }
}

// MARK: - Empty View

struct EmptyTranscriptionView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.ambiAccent.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "text.bubble")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.ambiAccent)
            }
            
            VStack(spacing: 8) {
                Text("No transcriptions yet")
                    .font(.headline)
                
                Text("Start speaking and your words\nwill appear here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    TranscriptionDetailView(session: Session(
        id: 1,
        title: "Test Session",
        date: Date()
    ))
    .environmentObject(AppState.shared)
    .frame(width: 700, height: 600)
}
