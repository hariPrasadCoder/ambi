import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            TranscriptionSettings()
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
            
            StorageSettings()
                .tabItem {
                    Label("Storage", systemImage: "internaldrive")
                }
            
            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 550, height: 450)
    }
}

// MARK: - General Settings

struct GeneralSettings: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        setDockVisibility(newValue)
                    }
            } header: {
                Text("Startup")
            }
            
            Section {
                HStack {
                    Text("Microphone")
                    Spacer()
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Request Access") {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in }
                        }
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
    
    private func setDockVisibility(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}

import AVFoundation

// MARK: - Transcription Settings

struct TranscriptionSettings: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("transcriptionInterval") private var transcriptionInterval = 30.0
    
    let models: [(id: String, name: String, size: String, accuracy: String)] = [
        ("tiny.en", "Tiny English", "~75 MB", "⭐"),
        ("base.en", "Base English", "~140 MB", "⭐⭐"),
        ("small.en", "Small English", "~460 MB", "⭐⭐⭐"),
        ("medium.en", "Medium English", "~1.5 GB", "⭐⭐⭐⭐"),
        ("large-v3-turbo", "Large v3 Turbo", "~1.5 GB", "⭐⭐⭐⭐⭐")
    ]
    
    var body: some View {
        Form {
            Section {
                ForEach(models, id: \.id) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                                .font(.headline)
                            
                            HStack(spacing: 8) {
                                Text(model.size)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text(model.accuracy)
                                    .font(.caption)
                            }
                        }
                        
                        Spacer()
                        
                        if appState.selectedModel == model.id {
                            if appState.isDownloadingModel {
                                ProgressView(value: appState.modelDownloadProgress)
                                    .frame(width: 60)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        } else {
                            Button("Select") {
                                appState.changeModel(to: model.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Whisper Model")
            } footer: {
                Text("Larger models are more accurate but require more memory and take longer to process.")
            }
            
            Section {
                Slider(value: $transcriptionInterval, in: 10...120, step: 10) {
                    Text("Processing Interval")
                } minimumValueLabel: {
                    Text("10s")
                } maximumValueLabel: {
                    Text("120s")
                }
                
                Text("Process audio every \(Int(transcriptionInterval)) seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Processing")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Storage Settings

struct StorageSettings: View {
    @State private var storageUsed: String = "Calculating..."
    @State private var transcriptionCount: Int = 0
    @State private var sessionCount: Int = 0
    
    var body: some View {
        Form {
            Section {
                LabeledContent("Storage Used", value: storageUsed)
                LabeledContent("Sessions", value: "\(sessionCount)")
                LabeledContent("Transcriptions", value: "\(transcriptionCount)")
            } header: {
                Text("Usage")
            }
            
            Section {
                Button("Open Storage Location") {
                    openStorageLocation()
                }
                
                Button("Export All Data") {
                    exportAllData()
                }
                
                Button("Clear All Data", role: .destructive) {
                    // Would show confirmation
                }
            } header: {
                Text("Data Management")
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await calculateStorage()
        }
    }
    
    private func calculateStorage() async {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ambiDir = appSupport.appendingPathComponent("Ambi")
        
        do {
            var totalSize: Int64 = 0
            
            if let enumerator = fileManager.enumerator(at: ambiDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    totalSize += Int64(resourceValues.fileSize ?? 0)
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            storageUsed = formatter.string(fromByteCount: totalSize)
            
            if let db = try? DatabaseManager() {
                transcriptionCount = (try? db.getTotalTranscriptionCount()) ?? 0
                sessionCount = (try? db.fetchAllSessions().count) ?? 0
            }
        } catch {
            storageUsed = "Unable to calculate"
        }
    }
    
    private func openStorageLocation() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ambiDir = appSupport.appendingPathComponent("Ambi")
        NSWorkspace.shared.open(ambiDir)
    }
    
    private func exportAllData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ambi-export.json"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Would export actual data
                try? "{}".write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            // App icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.ambiGradientStart, .ambiGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: 8) {
                Text("Ambi")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version 1.0.0")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Text("Always-on ambient voice recorder with local AI transcription.\n100% private. Everything stays on your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 12) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/hariPrasadCoder/ambi")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/hariPrasadCoder/ambi/issues")!)
            }
            .font(.subheadline)
            
            Spacer()
            
            Text("Made with ❤️ by Hari")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
