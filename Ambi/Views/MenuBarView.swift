import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            MenuBarHeader()
            
            Divider()
                .padding(.horizontal)
            
            // Current transcription preview
            if !appState.currentTranscription.isEmpty {
                CurrentTranscriptionPreview()
            }
            
            // Quick actions
            QuickActions()
            
            Divider()
                .padding(.horizontal)
            
            // Footer
            MenuBarFooter()
        }
        .frame(width: 320)
        .padding(.vertical, 8)
    }
}

struct MenuBarHeader: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack {
            // Status indicator
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: statusIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ambi")
                        .font(.headline)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Toggle recording
            Button(action: { appState.toggleRecording() }) {
                Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
            .help(appState.isPaused ? "Resume Recording" : "Pause Recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var statusColor: Color {
        if !appState.isRecording {
            return .gray
        }
        return appState.isPaused ? .orange : .green
    }
    
    private var statusIcon: String {
        if !appState.isRecording {
            return "mic.slash"
        }
        return appState.isPaused ? "pause.circle" : "mic"
    }
    
    private var statusText: String {
        if !appState.isRecording {
            return "Not recording"
        }
        return appState.isPaused ? "Paused" : "Recording active"
    }
}

struct CurrentTranscriptionPreview: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latest")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Just now")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            Text(appState.currentTranscription)
                .font(.subheadline)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct QuickActions: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 4) {
            // New session
            MenuBarButton(
                title: "New Session",
                icon: "plus.circle",
                action: { appState.startNewSession() }
            )
            
            // Open app
            MenuBarButton(
                title: "Open Ambi",
                icon: "macwindow",
                shortcut: "⌘O",
                action: openApp
            )
            
            // Settings
            MenuBarButton(
                title: "Settings...",
                icon: "gear",
                shortcut: "⌘,",
                action: { appState.showSettings = true }
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    private func openApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.title != "Ambi" || $0.isVisible == false }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

struct MenuBarButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                
                Text(title)
                    .font(.subheadline)
                
                Spacer()
                
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct MenuBarFooter: View {
    var body: some View {
        HStack {
            Text("v1.0.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            
            Spacer()
            
            Button("Quit Ambi") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
