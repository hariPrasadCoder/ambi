import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // Notch-style header with status
            NotchHeader()
            
            Divider()
                .opacity(0.5)
            
            // Live transcript preview
            if appState.isRecording && !appState.liveTranscript.isEmpty {
                LiveTranscriptView()
            }
            
            // Quick actions
            QuickActionsView()
            
            Divider()
                .opacity(0.5)
            
            // Footer
            FooterView()
        }
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Notch Header

struct NotchHeader: View {
    @EnvironmentObject var appState: AppState
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Status row
            HStack(spacing: 16) {
                // Recording indicator
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 44, height: 44)

                    // Pulse effect disabled to prevent UI shaking
                    // if appState.isRecording && !appState.isPaused {
                    //     Circle()
                    //         .fill(statusColor.opacity(0.3))
                    //         .frame(width: 44, height: 44)
                    //         .scaleEffect(isPulsing ? 1.3 : 1.0)
                    //         .opacity(isPulsing ? 0 : 0.5)
                    // }

                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ambi")
                        .font(.headline)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Model badge
                if appState.isModelLoaded {
                    Text(modelDisplayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                }
            }
            
            // Interactive controls
            HStack(spacing: 12) {
                // Record/Pause button
                ControlButton(
                    icon: appState.isPaused ? "play.fill" : "pause.fill",
                    label: appState.isPaused ? "Resume" : "Pause",
                    color: .orange,
                    action: { appState.toggleRecording() }
                )
                .disabled(!appState.isRecording)
                .opacity(appState.isRecording ? 1 : 0.5)
                
                // Open app button
                ControlButton(
                    icon: "macwindow",
                    label: "Open",
                    color: .purple,
                    action: openApp
                )
            }
        }
        .padding(16)
        // Pulse animation disabled to prevent UI shaking
        // .onAppear {
        //     startPulseAnimation()
        // }
        // .onChange(of: appState.isRecording) { newValue in
        //     if newValue && !appState.isPaused {
        //         startPulseAnimation()
        //     }
        // }
        // .onChange(of: appState.isPaused) { newValue in
        //     if !newValue && appState.isRecording {
        //         startPulseAnimation()
        //     }
        // }
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
        return appState.isPaused ? "pause.circle" : "mic.fill"
    }
    
    private var statusText: String {
        if appState.isDownloadingModel {
            return "Downloading model... \(Int(appState.modelDownloadProgress * 100))%"
        }
        if !appState.isModelLoaded {
            return "Loading model..."
        }
        if !appState.isRecording {
            return "Idle"
        }
        return appState.isPaused ? "Paused" : "Taking notes"
    }
    
    private var modelDisplayName: String {
        let model = appState.selectedModel
        if model.contains("tiny") { return "Tiny" }
        if model.contains("base") { return "Base" }
        if model.contains("small") { return "Small" }
        if model.contains("medium") { return "Medium" }
        if model.contains("large") { return "Large" }
        return model
    }
    
    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
    
    private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        // Find the main WindowGroup window (not a panel or popover)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Window was closed — trigger reopen which creates a new WindowGroup window
            _ = NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
        }
    }
}

struct ControlButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isHovered ? color.opacity(0.2) : color.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Live Transcript

struct LiveTranscriptView: View {
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                    
                    Text("Live")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Text(appState.liveTranscript)
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : 3)
                .animation(.easeOut(duration: 0.2), value: isExpanded)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Quick Actions

struct QuickActionsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 4) {
            MenuRowButton(
                icon: "gear",
                title: "Settings...",
                shortcut: "⌘,"
            ) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

struct MenuRowButton: View {
    let icon: String
    let title: String
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
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Footer

struct FooterView: View {
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
        .padding(.vertical, 10)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState.shared)
}
