import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Recording status header
            RecordingStatusHeader()
            
            Divider()
            
            // Session list
            List(selection: Binding(
                get: { appState.selectedSession?.id },
                set: { id in
                    if let id = id, let session = appState.sessions.first(where: { $0.id == id }) {
                        appState.selectSession(session)
                    }
                }
            )) {
                Section("Recent") {
                    ForEach(filteredSessions) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                    }
                    .onDelete(perform: deleteSession)
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Sessions")
    }
    
    private var filteredSessions: [Session] {
        if appState.searchQuery.isEmpty {
            return appState.sessions
        }
        return appState.searchTranscriptions()
    }
    
    private func deleteSession(at offsets: IndexSet) {
        for index in offsets {
            let session = filteredSessions[index]
            appState.deleteSession(session)
        }
    }
}

// MARK: - Recording Status Header

struct RecordingStatusHeader: View {
    @EnvironmentObject var appState: AppState
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Status indicator
            HStack(spacing: 12) {
                ZStack {
                    if appState.isRecording && !appState.isPaused {
                        Circle()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .scaleEffect(isPulsing ? 1.4 : 1.0)
                            .opacity(isPulsing ? 0 : 0.5)
                    }
                    
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            // Controls
            HStack(spacing: 12) {
                Button(action: { appState.toggleRecording() }) {
                    Label(
                        appState.isPaused ? "Resume" : (appState.isRecording ? "Pause" : "Record"),
                        systemImage: appState.isPaused ? "play.fill" : (appState.isRecording ? "pause.fill" : "record.circle")
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.isRecording && !appState.isPaused ? .orange : .green)
                .disabled(!appState.isModelLoaded)
                
                Button(action: { appState.startNewSession() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("New Session")
            }
        }
        .padding()
        .onAppear {
            if appState.isRecording && !appState.isPaused {
                startPulse()
            }
        }
        .onChange(of: appState.isRecording) { newValue in
            if newValue && !appState.isPaused {
                startPulse()
            }
        }
        .onChange(of: appState.isPaused) { newValue in
            if !newValue && appState.isRecording {
                startPulse()
            }
        }
    }
    
    private var statusColor: Color {
        if !appState.isRecording {
            return .gray
        }
        return appState.isPaused ? .orange : .green
    }
    
    private var statusTitle: String {
        if appState.isDownloadingModel {
            return "Downloading Model..."
        }
        if !appState.isModelLoaded {
            return "Loading Model..."
        }
        if !appState.isRecording {
            return "Not Recording"
        }
        return appState.isPaused ? "Paused" : "Recording"
    }
    
    private var statusSubtitle: String {
        if appState.isDownloadingModel {
            return "\(Int(appState.modelDownloadProgress * 100))% complete"
        }
        if !appState.isModelLoaded {
            return "Please wait..."
        }
        if !appState.isRecording {
            return "Click Record to start"
        }
        return appState.isPaused ? "Click Resume to continue" : "Listening to audio..."
    }
    
    private func startPulse() {
        withAnimation(.easeInOut(duration: 1).repeatForever()) {
            isPulsing = true
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    @EnvironmentObject var appState: AppState
    let session: Session
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: isToday ? "waveform" : "text.alignleft")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if isToday && appState.isRecording {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Transcription count
            if session.transcriptionCount > 0 {
                Text("\(session.transcriptionCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(session.date)
    }
    
    private var iconColor: Color {
        if isToday {
            return .ambiAccent
        }
        return .secondary
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState.shared)
        .frame(width: 280, height: 500)
}
