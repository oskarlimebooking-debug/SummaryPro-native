import AVFoundation
import Combine
import UIKit

final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var audioLevels: [Float] = Array(repeating: 0, count: 64)
    @Published var isBackgroundRecording = false

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var startTime: Date?
    private var tempFileURL: URL?

    // Crash recovery
    private var chunkURLs: [URL] = []
    private var chunkTimer: Timer?

    // Background / interruption observers
    private var interruptionObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    // MARK: - Audio Session

    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .mixWithOthers allows recording to continue when screen is off
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.setPreferredSampleRate(16000)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session configuration failed: \(error)")
        }
    }

    // MARK: - Recording

    func startRecording() throws -> Bool {
        configureSession()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let sessionId = UUID().uuidString
        let fileURL = tempDir.appendingPathComponent("recording_\(sessionId).wav")
        tempFileURL = fileURL

        // Create WAV file with proper settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: fileURL, settings: settings)
        audioFile = file

        // Install tap for recording and visualization
        let bufferSize: AVAudioFrameCount = 4096
        input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Write to file
            do {
                try file.write(from: buffer)
            } catch {
                print("Error writing audio buffer: \(error)")
            }

            // Update audio levels for visualizer
            self.updateAudioLevels(buffer: buffer)
        }

        try engine.start()
        audioEngine = engine
        inputNode = input
        isRecording = true
        startTime = Date()

        // Prevent screen from sleeping
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Register interruption and background handling
        registerInterruptionHandling()
        registerBackgroundHandling()

        // Start elapsed time timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            DispatchQueue.main.async {
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }

        // Start crash recovery chunks (save every 30s)
        startChunkRecovery(sessionId: sessionId)

        return true
    }

    func stopRecording() -> (url: URL, duration: String)? {
        guard isRecording else { return nil }

        // Stop engine and tap
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        audioFile = nil
        isRecording = false
        isBackgroundRecording = false

        // Stop timers
        timer?.invalidate()
        timer = nil
        chunkTimer?.invalidate()
        chunkTimer = nil

        // Remove observers
        removeObservers()

        // Re-enable screen sleep
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }

        // Calculate duration
        let duration = elapsedTime
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let durationStr = String(format: "%02d:%02d", minutes, seconds)

        // Clean up crash recovery files
        cleanupChunks()

        // Reset levels
        DispatchQueue.main.async {
            self.audioLevels = Array(repeating: 0, count: 64)
            self.elapsedTime = 0
        }

        guard let url = tempFileURL else { return nil }
        return (url: url, duration: durationStr)
    }

    // MARK: - Interruption Handling (screen off, phone calls, etc.)

    private func registerInterruptionHandling() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            switch type {
            case .began:
                // Interruption began (e.g. phone call) — engine pauses automatically
                print("Audio interruption began")

            case .ended:
                // Interruption ended — restart the engine if we were recording
                guard let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    do {
                        try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                        try self.audioEngine?.start()
                        print("Audio engine resumed after interruption")
                    } catch {
                        print("Failed to resume audio engine: \(error)")
                    }
                }

            @unknown default:
                break
            }
        }
    }

    // MARK: - Background / Foreground Handling

    private func registerBackgroundHandling() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            self.isBackgroundRecording = true
            print("App entered background — recording continues")

            // Ensure audio session stays active
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                print("Failed to keep audio session active in background: \(error)")
            }
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            self.isBackgroundRecording = false
            print("App returned to foreground — recording active")

            // Re-ensure audio engine is running
            if self.audioEngine?.isRunning == false {
                do {
                    try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
                    try self.audioEngine?.start()
                    print("Audio engine restarted on foreground return")
                } catch {
                    print("Failed to restart audio engine on foreground: \(error)")
                }
            }
        }
    }

    private func removeObservers() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            backgroundObserver = nil
        }
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
    }

    // MARK: - Audio Levels

    private func updateAudioLevels(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Simple FFT approximation: split into bands and get RMS
        let bandCount = 64
        let samplesPerBand = max(1, frameCount / bandCount)
        var levels = [Float](repeating: 0, count: bandCount)

        for band in 0..<bandCount {
            let start = band * samplesPerBand
            let end = min(start + samplesPerBand, frameCount)
            if start >= frameCount { break }

            var sum: Float = 0
            for i in start..<end {
                let sample = channelData[i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(end - start))
            // Normalize to 0-1 range, boost low values for visibility
            levels[band] = min(1.0, rms * 4.0)
        }

        DispatchQueue.main.async {
            self.audioLevels = levels
        }
    }

    // MARK: - Crash Recovery

    private func startChunkRecovery(sessionId: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp_recovery_\(sessionId)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        chunkTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self, let sourceURL = self.tempFileURL else { return }
            let chunkURL = tempDir.appendingPathComponent("chunk_\(self.chunkURLs.count).wav")
            try? FileManager.default.copyItem(at: sourceURL, to: chunkURL)
            self.chunkURLs.append(chunkURL)
        }
    }

    private func cleanupChunks() {
        for url in chunkURLs {
            try? FileManager.default.removeItem(at: url)
            // Also try to remove parent directory
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        chunkURLs = []
    }

    // MARK: - Utility

    var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func cleanupTempFile() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }

    deinit {
        removeObservers()
        if isRecording {
            _ = stopRecording()
        }
        cleanupTempFile()
    }
}
