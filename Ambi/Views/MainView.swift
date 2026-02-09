import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)
        } detail: {
            if let session = appState.selectedSession {
                TranscriptionDetailView(session: session)
            } else {
                EmptyStateView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if appState.isLoading {
                LoadingView()
            }
        }
        .searchable(text: $appState.searchQuery, placement: .sidebar, prompt: "Search transcriptions")
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            
            Text("No Session Selected")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            Text("Select a session from the sidebar to view its transcription")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            if appState.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(appState.isPaused ? .orange : .red)
                        .frame(width: 8, height: 8)
                        .opacity(appState.isPaused ? 1 : 0.8)
                    
                    Text(appState.isPaused ? "Recording Paused" : "Recording...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingView: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.9)
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(lineWidth: 4)
                        .opacity(0.1)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(rotation))
                }
                
                VStack(spacing: 8) {
                    Text("Loading Ambi")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Preparing transcription engine...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Color Extensions

extension Color {
    static let ambiAccent = Color(red: 0.4, green: 0.5, blue: 1.0)
    static let ambiGradientStart = Color(red: 0.4, green: 0.5, blue: 1.0)
    static let ambiGradientEnd = Color(red: 0.7, green: 0.4, blue: 1.0)
}

#Preview {
    MainView()
        .environmentObject(AppState.shared)
        .frame(width: 1000, height: 700)
}
