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
                LoadingOverlay(message: appState.loadingMessage)
            }
            
            if appState.isDownloadingModel {
                ModelDownloadOverlay(progress: appState.modelDownloadProgress)
            }
        }
        .searchable(text: $appState.searchQuery, placement: .sidebar, prompt: "Search transcriptions")
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.ambiAccent.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "waveform.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.ambiAccent)
            }
            
            VStack(spacing: 8) {
                Text("No Session Selected")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Select a session from the sidebar\nor start speaking to create one")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if appState.isRecording && !appState.isPaused {
                RecordingIndicatorBadge()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecordingIndicatorBadge: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isAnimating ? 1.2 : 1.0)

            Text("Taking notes...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.green.opacity(0.1)))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.95)
            
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
                                colors: [.ambiGradientStart, .ambiGradientEnd],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(rotation))
                }
                
                VStack(spacing: 8) {
                    Text("Loading")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(message)
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

// MARK: - Model Download Overlay

struct ModelDownloadOverlay: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                
                VStack(spacing: 8) {
                    Text("Downloading Whisper Model")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text("This is a one-time download")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.ambiAccent)
                        .frame(width: 200)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.15))
            )
        }
        .transition(.opacity)
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
