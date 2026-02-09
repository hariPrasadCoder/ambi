import SwiftUI

struct TranscriptionDetailView: View {
    @EnvironmentObject var appState: AppState
    let session: Session
    
    @State private var transcriptions: [Transcription] = []
    @State private var isLoading = true
    @State private var hoveredId: Int64?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeader(session: session)
            
            Divider()
            
            // Content
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if transcriptions.isEmpty {
                EmptyTranscriptionView()
            } else {
                TranscriptionContent(
                    transcriptions: transcriptions,
                    hoveredId: $hoveredId
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await loadTranscriptions()
        }
        .onChange(of: session.id) { _, _ in
            Task { await loadTranscriptions() }
        }
        .onChange(of: appState.currentTranscription) { _, _ in
            // Refresh when new transcription comes in
            if appState.selectedSession?.id == session.id {
                Task { await loadTranscriptions() }
            }
        }
    }
    
    private func loadTranscriptions() async {
        isLoading = true
        
        // Simulate loading from database
        do {
            let db = try DatabaseManager()
            if let id = session.id {
                transcriptions = try db.fetchTranscriptions(forSession: id)
            }
        } catch {
            print("Failed to load transcriptions: \(error)")
        }
        
        isLoading = false
    }
}

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
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Copy button
                Button(action: copyAll) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(HeaderButtonStyle())
                .help("Copy all transcriptions")
                
                // Export button
                Button(action: exportSession) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(HeaderButtonStyle())
                .help("Export session")
                
                // More options
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
        // Copy all transcriptions to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Would need actual transcription text here
        pasteboard.setString("Transcription copied", forType: .string)
    }
    
    private func exportSession() {
        // Export session to file
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(session.displayTitle).txt"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Would write actual transcription text here
                try? "Exported transcription".write(to: url, atomically: true, encoding: .utf8)
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
                    .fill(configuration.isPressed 
                        ? Color.primary.opacity(0.1) 
                        : Color.clear
                    )
            )
            .foregroundStyle(.secondary)
    }
}

struct TranscriptionContent: View {
    let transcriptions: [Transcription]
    @Binding var hoveredId: Int64?
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(transcriptions) { transcription in
                    TranscriptionBlock(
                        transcription: transcription,
                        isHovered: hoveredId == transcription.id
                    )
                    .onHover { isHovered in
                        hoveredId = isHovered ? transcription.id : nil
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }
}

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
            
            // Divider line
            Rectangle()
                .fill(Color.ambiAccent.opacity(0.3))
                .frame(width: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            
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
                    .fill(isHovered 
                        ? Color.primary.opacity(0.03) 
                        : Color.clear
                    )
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

struct EmptyTranscriptionView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.ambiAccent.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "text.bubble")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.ambiAccent)
            }
            
            Text("No transcriptions yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Start speaking and your words will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if appState.isRecording && !appState.isPaused {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    
                    Text("Listening...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            
            Spacer()
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
