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
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettings: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("showInDock") private var showInDock = false
    @AppStorage("playSoundOnTranscription") private var playSoundOnTranscription = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        setLaunchAtLogin(newValue)
                    }
                
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { newValue in
                        setDockVisibility(newValue)
                    }
            } header: {
                Text("Startup")
            }
            
            Section {
                Toggle("Play sound on new transcription", isOn: $playSoundOnTranscription)
            } header: {
                Text("Notifications")
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

struct TranscriptionSettings: View {
    @AppStorage("whisperModel") private var whisperModel = "large-v3-turbo"
    @AppStorage("transcriptionInterval") private var transcriptionInterval = 30.0
    @AppStorage("language") private var language = "en"
    
    let models = [
        ("tiny", "Tiny (~75MB) - Fastest"),
        ("tiny.en", "Tiny English (~75MB)"),
        ("base", "Base (~142MB)"),
        ("base.en", "Base English (~142MB)"),
        ("small", "Small (~466MB)"),
        ("small.en", "Small English (~466MB)"),
        ("medium", "Medium (~1.5GB)"),
        ("medium.en", "Medium English (~1.5GB)"),
        ("large-v3", "Large v3 (~3GB) - Most Accurate"),
        ("large-v3-turbo", "Large v3 Turbo (~1.5GB) - Recommended")
    ]
    
    let languages = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("auto", "Auto-detect")
    ]
    
    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $whisperModel) {
                    ForEach(models, id: \.0) { model in
                        Text(model.1).tag(model.0)
                    }
                }
                
                Text("Larger models are more accurate but use more memory and CPU")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Whisper Model")
            }
            
            Section {
                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.0) { lang in
                        Text(lang.1).tag(lang.0)
                    }
                }
            } header: {
                Text("Language")
            }
            
            Section {
                Slider(value: $transcriptionInterval, in: 10...120, step: 10) {
                    Text("Transcription interval")
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

struct StorageSettings: View {
    @State private var storageUsed: String = "Calculating..."
    @State private var transcriptionCount: Int = 0
    
    var body: some View {
        Form {
            Section {
                LabeledContent("Storage Used", value: storageUsed)
                LabeledContent("Total Transcriptions", value: "\(transcriptionCount)")
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
                    // Would show confirmation dialog
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
            let contents = try fileManager.contentsOfDirectory(at: ambiDir, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0
            
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(resourceValues.fileSize ?? 0)
            }
            
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            storageUsed = formatter.string(fromByteCount: totalSize)
            
            // Get transcription count
            if let db = try? DatabaseManager() {
                transcriptionCount = (try? db.getTotalTranscriptionCount()) ?? 0
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
                // Would export actual data here
                try? "{}".write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

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
}
