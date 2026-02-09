import Foundation
import AVFoundation

final class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: [Float] = []
    private var bufferLock = NSLock()
    private var transcriptionTimer: Timer?
    private var isPaused = false
    
    private let sampleRate: Double = 16000 // Whisper expects 16kHz
    private let bufferDuration: TimeInterval = 30 // Process every 30 seconds
    
    var onAudioReady: ((Data) -> Void)?
    
    init(onAudioReady: @escaping (Data) -> Void) {
        self.onAudioReady = onAudioReady
        super.init()
    }
    
    func startRecording() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            setupAudioEngine()
            startTranscriptionTimer()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupAudioEngine()
                        self?.startTranscriptionTimer()
                    }
                }
            }
        case .denied, .restricted:
            print("Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone")
        @unknown default:
            break
        }
    }
    
    func stopRecording() {
        transcriptionTimer?.invalidate()
        transcriptionTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
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
        // Clear buffer to start fresh
        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()
    }
    
    private func setupAudioEngine() {
        // Don't setup if already running
        if audioEngine?.isRunning == true {
            return
        }
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        inputNode = engine.inputNode
        guard let input = inputNode else { return }
        
        let inputFormat = input.outputFormat(forBus: 0)
        
        // Create format for Whisper (16kHz mono)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return }
        
        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            print("Failed to create audio converter")
            return
        }
        
        // Install tap on input node
        let bufferSize: AVAudioFrameCount = 4096
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, !self.isPaused else { return }
            
            // Convert to 16kHz mono
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
            )
            
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCount
            ) else { return }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                print("Conversion error: \(error)")
                return
            }
            
            // Append to buffer
            if let channelData = convertedBuffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(
                    start: channelData,
                    count: Int(convertedBuffer.frameLength)
                ))
                
                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: samples)
                self.bufferLock.unlock()
            }
        }
        
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func startTranscriptionTimer() {
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
        guard energy > 0.001 else { return } // Skip if too quiet
        
        // Convert to Data
        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        // Callback to transcribe
        DispatchQueue.main.async { [weak self] in
            self?.onAudioReady?(data)
        }
    }
}

// MARK: - Audio Utilities

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
