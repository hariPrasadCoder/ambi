import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            SidebarHeader()
            
            Divider()
                .padding(.horizontal)
            
            // Sessions List
            if appState.sessions.isEmpty {
                EmptySidebarView()
            } else {
                SessionsList()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

struct SidebarHeader: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Logo and title
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.ambiGradientStart, .ambiGradientEnd],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    
                    Text("Ambi")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Recording status
                RecordingIndicator()
            }
            
            // Quick stats
            HStack(spacing: 16) {
                StatBadge(
                    icon: "calendar",
                    value: "\(appState.sessions.count)",
                    label: "Sessions"
                )
                
                StatBadge(
                    icon: "clock",
                    value: "Today",
                    label: appState.isRecording ? "Active" : "Paused"
                )
            }
        }
        .padding()
    }
}

struct RecordingIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isPulsing = false
    
    var body: some View {
        Button(action: { appState.toggleRecording() }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                
                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(indicatorColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onAppear {
            if appState.isRecording && !appState.isPaused {
                withAnimation(.easeInOut(duration: 1).repeatForever()) {
                    isPulsing = true
                }
            }
        }
        .onChange(of: appState.isRecording) { _, newValue in
            if newValue && !appState.isPaused {
                withAnimation(.easeInOut(duration: 1).repeatForever()) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }
    
    private var indicatorColor: Color {
        if !appState.isRecording {
            return .gray
        }
        return appState.isPaused ? .orange : .red
    }
    
    private var statusText: String {
        if !appState.isRecording {
            return "Stopped"
        }
        return appState.isPaused ? "Paused" : "Recording"
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct SessionsList: View {
    @EnvironmentObject var appState: AppState
    
    private var groupedSessions: [(String, [Session])] {
        let sessions = appState.searchQuery.isEmpty 
            ? appState.sessions 
            : appState.searchTranscriptions()
        
        let grouped = Dictionary(grouping: sessions) { session -> String in
            if Calendar.current.isDateInToday(session.date) {
                return "Today"
            } else if Calendar.current.isDateInYesterday(session.date) {
                return "Yesterday"
            } else if Calendar.current.isDate(session.date, equalTo: Date(), toGranularity: .weekOfYear) {
                return "This Week"
            } else if Calendar.current.isDate(session.date, equalTo: Date(), toGranularity: .month) {
                return "This Month"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: session.date)
            }
        }
        
        let order = ["Today", "Yesterday", "This Week", "This Month"]
        return grouped.sorted { first, second in
            let idx1 = order.firstIndex(of: first.key) ?? Int.max
            let idx2 = order.firstIndex(of: second.key) ?? Int.max
            if idx1 != idx2 { return idx1 < idx2 }
            return first.key > second.key
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groupedSessions, id: \.0) { group, sessions in
                    Section {
                        ForEach(sessions) { session in
                            SessionRow(session: session)
                        }
                    } header: {
                        SectionHeader(title: group)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }
}

struct SessionRow: View {
    @EnvironmentObject var appState: AppState
    let session: Session
    
    private var isSelected: Bool {
        appState.selectedSession?.id == session.id
    }
    
    var body: some View {
        Button(action: { appState.selectedSession = session }) {
            HStack(spacing: 12) {
                // Date indicator
                VStack(spacing: 2) {
                    Text(session.shortDate.components(separatedBy: " ").first ?? "")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    Text(session.shortDate.components(separatedBy: " ").last ?? "")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .frame(width: 40)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white : .primary)
                    
                    Text(session.timeString)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected 
                        ? LinearGradient(
                            colors: [.ambiGradientStart, .ambiGradientEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                          )
                        : LinearGradient(
                            colors: [Color.clear, Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                          )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                appState.deleteSession(session)
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        }
    }
}

struct EmptySidebarView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            
            Text("No recordings yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Start speaking and Ambi will\nautomatically capture your voice")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState.shared)
        .frame(width: 300, height: 600)
}
