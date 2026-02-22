import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.12, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        ForEach(0..<3) { step in
                            Capsule()
                                .fill(step <= currentStep ? Color.ambiAccent : Color.white.opacity(0.2))
                                .frame(width: step == currentStep ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentStep)
                        }
                    }
                    Text(["Welcome", "Permissions", "Model"][currentStep])
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .animation(.easeOut, value: currentStep)
                }
                .padding(.top, 40)
                
                Spacer()
                
                // Content
                TabView(selection: $currentStep) {
                    WelcomeStep()
                        .tag(0)
                    
                    PermissionStep()
                        .tag(1)
                    
                    ModelStep()
                        .tag(2)
                }
                // Note: Using default tab style for macOS compatibility
                
                Spacer()
                
                // Navigation
                HStack {
                    if currentStep > 0 {
                        Button(action: { withAnimation { currentStep -= 1 } }) {
                            Text("Back")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }

                    Spacer()

                    Button(action: nextStep) {
                        HStack(spacing: 8) {
                            Text(currentStep == 2 ? "Get Started" : "Continue")
                                .font(.headline)

                            Image(systemName: "arrow.right")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.ambiGradientStart, .ambiGradientEnd],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(currentStep == 1 && !appState.hasMicrophonePermission)
                    .opacity(currentStep == 1 && !appState.hasMicrophonePermission ? 0.5 : 1)
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func nextStep() {
        if currentStep < 2 {
            withAnimation(.spring(response: 0.4)) {
                currentStep += 1
            }
        } else {
            appState.completeOnboarding()
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    @State private var isAnimating = false
    @State private var visibleFeatures = 0

    private let features: [(icon: String, title: String, description: String)] = [
        ("mic.fill", "Always-on Recording", "Runs quietly in your menu bar"),
        ("cpu", "Local AI", "Whisper transcription, 100% private"),
        ("magnifyingglass", "Searchable", "Find any conversation instantly")
    ]

    var body: some View {
        VStack(spacing: 32) {
            // Animated logo
            ZStack {
                // Second outer ring (new)
                Circle()
                    .stroke(Color.ambiGradientEnd.opacity(0.3), lineWidth: 1)
                    .frame(width: 200, height: 200)
                    .scaleEffect(isAnimating ? 1.15 : 0.9)
                    .opacity(isAnimating ? 0.2 : 0.6)
                    .animation(
                        .easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(0.6),
                        value: isAnimating
                    )

                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.ambiGradientStart.opacity(0.5), .ambiGradientEnd.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .opacity(isAnimating ? 0.5 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)

                // Inner circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.ambiGradientStart, .ambiGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                // Waveform icon
                Image(systemName: "waveform")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .onAppear {
                isAnimating = true
                // Stagger feature rows
                for i in 0..<3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.25 + 0.4) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            visibleFeatures = i + 1
                        }
                    }
                }
            }

            VStack(spacing: 16) {
                Text("Welcome to Ambi")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                Text("Your personal ambient voice recorder.\nCapture every conversation, transcribed locally with AI.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Staggered feature rows
            VStack(alignment: .leading, spacing: 16) {
                ForEach(features.indices, id: \.self) { i in
                    if i < visibleFeatures {
                        FeatureRow(
                            icon: features[i].icon,
                            title: features[i].title,
                            description: features[i].description
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 60)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.ambiAccent)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Permission Step

struct PermissionStep: View {
    @EnvironmentObject var appState: AppState
    @State private var isRequesting = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                Circle()
                    .fill(appState.hasMicrophonePermission ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: appState.hasMicrophonePermission ? "checkmark.circle.fill" : "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(appState.hasMicrophonePermission ? .green : .orange)
            }
            
            VStack(spacing: 16) {
                Text(appState.hasMicrophonePermission ? "Microphone Access Granted" : "Microphone Access Required")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                
                Text(appState.hasMicrophonePermission 
                     ? "You're all set! Ambi can now record and transcribe your voice."
                     : "Ambi needs microphone access to record and transcribe your voice. Your audio is processed locally and never leaves your device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            if !appState.hasMicrophonePermission {
                Button(action: requestPermission) {
                    HStack(spacing: 8) {
                        if isRequesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Grant Access")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.orange)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
            }
        }
        .padding(.horizontal, 60)
    }
    
    private func requestPermission() {
        isRequesting = true
        Task {
            _ = await appState.requestMicrophonePermission()
            isRequesting = false
        }
    }
}

// MARK: - Model Step

struct ModelStep: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedModel = "base.en"
    
    let models: [(id: String, name: String, size: String, description: String)] = [
        ("tiny.en", "Tiny", "~75 MB", "Fastest, lower accuracy"),
        ("base.en", "Base", "~140 MB", "Good balance (recommended)"),
        ("small.en", "Small", "~460 MB", "Better accuracy"),
        ("medium.en", "Medium", "~1.5 GB", "High accuracy"),
        ("large-v3-turbo", "Large Turbo", "~1.5 GB", "Best accuracy")
    ]
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Text("Choose Transcription Model")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Larger models are more accurate but require more memory.\nYou can change this later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Model selector
            VStack(spacing: 12) {
                ForEach(models, id: \.id) { model in
                    ModelOption(
                        name: model.name,
                        size: model.size,
                        description: model.description,
                        isSelected: selectedModel == model.id
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedModel = model.id
                            appState.selectedModel = model.id
                            UserDefaults.standard.set(model.id, forKey: "selectedModel")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            
            // Download note
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                
                Text("The model will download on first launch (~\(selectedModelSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 60)
        .onAppear {
            selectedModel = appState.selectedModel
        }
    }
    
    private var selectedModelSize: String {
        models.first { $0.id == selectedModel }?.size ?? "varies"
    }
}

struct ModelOption: View {
    let name: String
    let size: String
    let description: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.ambiAccent : Color.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.ambiAccent.opacity(0.15) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.ambiAccent : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState.shared)
        .frame(width: 800, height: 600)
}
