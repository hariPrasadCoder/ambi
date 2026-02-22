import Foundation
import AVFoundation

class AudioRecorder: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var bufferLock = NSLock()
    private let transcriptionCallback: (Data) -> Void
    private var processingTimer: Timer?
    
    // State flags
    private var hasRequestedPermission = false
    private var isSetup = false
    
    @Published var isRecording = false
    @Published var isPaused = false
    
    // Callbacks
    var onRecordingStarted: (() -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onAudioLevelChanged: ((Float) -> Void)?
    
    // Settings
    private let sampleRate: Double = 16000
    private let processingInterval: TimeInterval
    
    init(processingInterval: TimeInterval = 30.0, transcriptionCallback: @escaping (Data) -> Void) {
        self.processingInterval = processingInterval
        self.transcriptionCallback = transcriptionCallback
        super.init()
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        checkMicrophonePermission { [weak self] granted in
            guard let self = self, granted else {
                DispatchQueue.main.async {
                    self?.onPermissionDenied?()
                }
                return
            }
            
            DispatchQueue.main.async {
                self.setupAndStartRecording()
            }
        }
    }
    
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            completion(true)
            
        case .notDetermined:
            guard !hasRequestedPermission else {
                completion(false)
                return
            }
            hasRequestedPermission = true
            
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
            
        case .denied, .restricted:
            completion(false)
            
        @unknown default:
            completion(false)
        }
    }
    
    private func setupAndStartRecording() {
        guard !isSetup else {
            resumeRecording()
            return
        }
        
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else {
            print("AudioRecorder: Failed to create audio engine")
            return
        }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create output format at 16kHz mono for Whisper
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("AudioRecorder: Failed to create output format")
            return
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("AudioRecorder: Failed to create converter from \(inputFormat) to \(outputFormat)")
            return
        }
        
        // Install tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, !self.isPaused else { return }
            self.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }
        
        do {
            try engine.start()
            isRecording = true
            isPaused = false
            isSetup = true
            
            // Start processing timer
            startProcessingTimer()
            
            onRecordingStarted?()
            print("AudioRecorder: Recording started")
        } catch {
            print("AudioRecorder: Failed to start engine: \(error)")
            isRecording = false
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)
        
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("AudioRecorder: Conversion error: \(error)")
            return
        }
        
        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))
        
        bufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        bufferLock.unlock()

        if !samples.isEmpty {
            let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
            DispatchQueue.main.async { [weak self] in
                self?.onAudioLevelChanged?(min(rms * 10, 1.0))
            }
        }
    }
    
    private func startProcessingTimer() {
        processingTimer?.invalidate()
        processingTimer = Timer.scheduledTimer(withTimeInterval: processingInterval, repeats: true) { [weak self] _ in
            self?.processAccumulatedAudio()
        }
    }
    
    private func processAccumulatedAudio() {
        guard isRecording, !isPaused else { return }
        
        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        guard !samples.isEmpty else { return }
        
        // Check if audio has actual content (not silence)
        // Threshold lowered to 0.004 to catch quiet but real speech
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        guard rms > 0.004 else {
            print("AudioRecorder: Audio too quiet (rms=\(String(format: "%.5f", rms))), skipping")
            return
        }
        
        // Convert to Data
        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        print("AudioRecorder: Processing \(samples.count) samples, RMS: \(rms)")
        transcriptionCallback(data)
    }
    
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        processingTimer?.invalidate()
        
        // Process any remaining audio immediately
        processAccumulatedAudio()
        
        print("AudioRecorder: Paused")
    }
    
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        startProcessingTimer()
        print("AudioRecorder: Resumed")
    }
    
    func stopRecording() {
        processingTimer?.invalidate()
        processingTimer = nil
        
        // Process remaining audio
        processAccumulatedAudio()
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        isRecording = false
        isPaused = false
        isSetup = false
        
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        print("AudioRecorder: Stopped")
    }
    
    func startNewSession() {
        // Process any remaining audio first
        processAccumulatedAudio()
        
        // Clear buffer for new session
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        print("AudioRecorder: Started new session")
    }
    
    deinit {
        stopRecording()
    }
}
