import SwiftUI

struct TranscriptionDetailView: View {
    @EnvironmentObject var appState: AppState
    let session: Session
    
    @State private var hoveredId: Int64?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeader(session: session)
            
            Divider()
            
            // Content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        // Live transcript section (if recording this session)
                        if isCurrentSession && appState.isRecording {
                            LiveTranscriptSection()
                        }
                        
                        // Historical transcriptions
                        if appState.transcriptions.isEmpty && !appState.isRecording {
                            EmptyTranscriptionView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 100)
                        } else {
                            ForEach(appState.transcriptions) { transcription in
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
                    // Scroll to latest
                    if let lastId = appState.transcriptions.last?.id {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var isCurrentSession: Bool {
        guard let sessionDate = Calendar.current.dateComponents([.year, .month, .day], from: session.date).date else {
            return false
        }
        let today = Calendar.current.startOfDay(for: Date())
        let sessionDay = Calendar.current.startOfDay(for: session.date)
        return today == sessionDay
    }
}

// MARK: - Detail Header

struct DetailHeader: View {
    @EnvironmentObject var appState: AppState
    let session: Session
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
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

// MARK: - Live Transcript Section

struct LiveTranscriptSection: View {
    @EnvironmentObject var appState: AppState
    @State private var isPulsing = false
    
    var body: some View {
        if !appState.liveTranscript.isEmpty || (appState.isRecording && !appState.isPaused) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0.6 : 1.0)
                    
                    Text("Live Transcription")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if appState.isPaused {
                        Text("PAUSED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                    }
                }
                
                // Content
                if appState.liveTranscript.isEmpty && !appState.isPaused {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        
                        Text("Listening...")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(appState.liveTranscript)
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundStyle(appState.isPaused ? .primary : .secondary)
                        .animation(.easeOut(duration: 0.2), value: appState.liveTranscript)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding(.bottom, 16)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                    isPulsing = true
                }
            }
        }
    }
}

// MARK: - Transcription Block

struct TranscriptionBlock: View {
    let transcription: Transcription
    let isHovered: Bool
    
    @State private var isCopied = false
    
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
                
                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: copyText) {
                            Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
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
    }
    
    private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcription.text, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
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
