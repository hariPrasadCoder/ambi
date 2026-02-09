import Foundation
import AVFoundation

final class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private var bufferLock = NSLock()
    private var transcriptionTimer: Timer?
    private var isPaused = false
    private var hasRequestedPermission = false
    private var isSetup = false
    
    private let sampleRate: Double = 16000 // Whisper expects 16kHz
    private let bufferDuration: TimeInterval = 30 // Process every 30 seconds
    
    var onAudioReady: ((Data) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onRecordingStarted: (() -> Void)?
    
    init(onAudioReady: @escaping (Data) -> Void) {
        self.onAudioReady = onAudioReady
        super.init()
    }
    
    func startRecording() {
        // Prevent multiple calls
        guard !isSetup else {
            print("AudioRecorder: Already setup, skipping")
            return
        }
        
        checkAndRequestPermission()
    }
    
    private func checkAndRequestPermission() {
        // Prevent requesting multiple times
        guard !hasRequestedPermission else {
            print("AudioRecorder: Permission already requested")
            return
        }
        
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("AudioRecorder: Current permission status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            print("AudioRecorder: Permission authorized, starting engine")
            DispatchQueue.main.async { [weak self] in
                self?.setupAndStart()
            }
            
        case .notDetermined:
            hasRequestedPermission = true
            print("AudioRecorder: Requesting permission...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                print("AudioRecorder: Permission response: \(granted)")
                DispatchQueue.main.async {
                    if granted {
                        self?.setupAndStart()
                    } else {
                        self?.onPermissionDenied?()
                    }
                }
            }
            
        case .denied, .restricted:
            print("AudioRecorder: Permission denied or restricted")
            onPermissionDenied?()
            
        @unknown default:
            print("AudioRecorder: Unknown permission status")
            break
        }
    }
    
    private func setupAndStart() {
        guard !isSetup else {
            print("AudioRecorder: Already setup")
            return
        }
        
        print("AudioRecorder: Setting up audio engine...")
        
        do {
            try setupAudioEngine()
            startTranscriptionTimer()
            isSetup = true
            onRecordingStarted?()
            print("AudioRecorder: Successfully started")
        } catch {
            print("AudioRecorder: Failed to setup: \(error)")
        }
    }
    
    func stopRecording() {
        print("AudioRecorder: Stopping...")
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil
        
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        isSetup = false
    }
    
    func pauseRecording() {
        isPaused = true
        audioEngine?.pause()
    }
    
    func resumeRecording() {
        isPaused = false
        try? audioEngine?.start()
    }
    
    func startNewSession() {
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
    }
    
    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("AudioRecorder: Input format - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")
        
        // Validate input format
        guard inputFormat.sampleRate > 0 else {
            throw AudioRecorderError.invalidInputFormat
        }
        
        // Create format for Whisper (16kHz mono)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.cannotCreateOutputFormat
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioRecorderError.cannotCreateConverter
        }
        
        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, !self.isPaused else { return }
            self.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }
        
        engine.prepare()
        try engine.start()
        
        self.audioEngine = engine
        print("AudioRecorder: Engine started successfully")
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate
        )
        
        guard frameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if error != nil { return }
        
        if let channelData = convertedBuffer.floatChannelData?[0] {
            let samples = Array(UnsafeBufferPointer(
                start: channelData,
                count: Int(convertedBuffer.frameLength)
            ))
            
            bufferLock.lock()
            audioBuffer.append(contentsOf: samples)
            bufferLock.unlock()
        }
    }
    
    private func startTranscriptionTimer() {
        // Invalidate existing timer
        transcriptionTimer?.invalidate()
        
        transcriptionTimer = Timer.scheduledTimer(withTimeInterval: bufferDuration, repeats: true) { [weak self] _ in
            self?.processBuffer()
        }
    }
    
    private func processBuffer() {
        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()
        
        guard !samples.isEmpty else { return }
        
        // Check if there's actual audio (not silence)
        let energy = samples.reduce(0) { $0 + abs($1) } / Float(samples.count)
        guard energy > 0.001 else { return }
        
        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.onAudioReady?(data)
        }
    }
}

// MARK: - Errors

enum AudioRecorderError: Error {
    case invalidInputFormat
    case cannotCreateOutputFormat
    case cannotCreateConverter
}

// MARK: - Utilities

extension AudioRecorder {
    static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
