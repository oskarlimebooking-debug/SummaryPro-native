import Foundation
import AVFoundation

enum WhisperService {
    private static let apiURL = "https://api.openai.com/v1/audio/transcriptions"
    private static let maxChunkMB = 24

    static func transcribe(
        audioURL: URL,
        language: String,
        model: String,
        apiKey: String,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw WhisperError.noApiKey
        }

        let audioData = try Data(contentsOf: audioURL)
        let fileSizeMB = Double(audioData.count) / (1024 * 1024)
        let languageCode = language.components(separatedBy: "-").first ?? language

        if fileSizeMB <= Double(maxChunkMB) {
            onProgress(0.2, "Pošiljanje na OpenAI Whisper API...")
            return try await transcribeSingle(
                audioData: audioData,
                model: model,
                language: languageCode,
                apiKey: apiKey
            )
        } else {
            return try await transcribeChunked(
                audioURL: audioURL,
                model: model,
                language: languageCode,
                apiKey: apiKey,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Single Upload

    private static func transcribeSingle(
        audioData: Data,
        model: String,
        language: String,
        apiKey: String
    ) async throws -> String {
        let boundary = UUID().uuidString
        var body = Data()

        // File field
        body.appendMultipart(boundary: boundary, name: "file", filename: "audio.wav", mimeType: "audio/wav", data: audioData)
        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: model)
        // Language field
        body.appendMultipart(boundary: boundary, name: "language", value: language)
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = parseErrorMessage(from: data) ?? "Whisper API napaka \(httpResponse.statusCode)"
            throw WhisperError.apiError(errorMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw WhisperError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Chunked Upload (for large files)

    private static func transcribeChunked(
        audioURL: URL,
        model: String,
        language: String,
        apiKey: String,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> String {
        onProgress(0.15, "Dekodiranje zvoka za razdelitev...")

        // Read audio file
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(audioFile.length)

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw WhisperError.noAudioData
        }

        let totalSamples = Int(buffer.frameLength)

        // 10 minutes per chunk (~19MB in 16-bit mono WAV at 16kHz)
        let chunkSeconds = 600
        let overlapSeconds = 10
        let samplesPerChunk = Int(sampleRate) * chunkSeconds
        let overlapSamples = Int(sampleRate) * overlapSeconds
        let totalChunks = (totalSamples + samplesPerChunk - 1) / samplesPerChunk

        var transcripts: [String] = []

        for i in 0..<totalChunks {
            let start = i * samplesPerChunk
            let end = min(start + samplesPerChunk + overlapSamples, totalSamples)
            let chunkSamples = end - start

            let progress = 0.2 + Double(i + 1) / Double(totalChunks) * 0.35
            onProgress(progress, "Prepisovanje dela \(i + 1)/\(totalChunks)...")

            // Create WAV data for this chunk
            let wavData = createWAVData(from: channelData, offset: start, count: chunkSamples, sampleRate: Int(sampleRate))

            let text = try await transcribeSingle(
                audioData: wavData,
                model: model,
                language: language,
                apiKey: apiKey
            )
            if !text.isEmpty {
                transcripts.append(text)
            }
        }

        return transcripts.joined(separator: " ")
    }

    // MARK: - WAV Creation

    private static func createWAVData(from data: UnsafePointer<Float>, offset: Int, count: Int, sampleRate: Int) -> Data {
        let numChannels = 1
        let bytesPerSample = 2
        let dataLength = count * numChannels * bytesPerSample
        let headerSize = 44

        var wavData = Data(count: headerSize + dataLength)

        wavData.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)

            // RIFF header
            writeString(bytes, offset: 0, string: "RIFF")
            writeUInt32LE(bytes, offset: 4, value: UInt32(36 + dataLength))
            writeString(bytes, offset: 8, string: "WAVE")

            // fmt chunk
            writeString(bytes, offset: 12, string: "fmt ")
            writeUInt32LE(bytes, offset: 16, value: 16) // chunk size
            writeUInt16LE(bytes, offset: 20, value: 1)  // PCM format
            writeUInt16LE(bytes, offset: 22, value: UInt16(numChannels))
            writeUInt32LE(bytes, offset: 24, value: UInt32(sampleRate))
            writeUInt32LE(bytes, offset: 28, value: UInt32(sampleRate * numChannels * bytesPerSample))
            writeUInt16LE(bytes, offset: 32, value: UInt16(numChannels * bytesPerSample))
            writeUInt16LE(bytes, offset: 34, value: 16) // bits per sample

            // data chunk
            writeString(bytes, offset: 36, string: "data")
            writeUInt32LE(bytes, offset: 40, value: UInt32(dataLength))

            // Audio samples
            let int16Buffer = UnsafeMutableRawPointer(bytes.baseAddress! + headerSize)
                .bindMemory(to: Int16.self, capacity: count)
            for i in 0..<count {
                let sample = max(-1.0, min(1.0, data[offset + i]))
                int16Buffer[i] = sample < 0 ? Int16(sample * 32768.0) : Int16(sample * 32767.0)
            }
        }

        return wavData
    }

    private static func writeString(_ buffer: UnsafeMutableBufferPointer<UInt8>, offset: Int, string: String) {
        for (i, char) in string.utf8.enumerated() {
            buffer[offset + i] = char
        }
    }

    private static func writeUInt32LE(_ buffer: UnsafeMutableBufferPointer<UInt8>, offset: Int, value: UInt32) {
        buffer[offset] = UInt8(value & 0xFF)
        buffer[offset + 1] = UInt8((value >> 8) & 0xFF)
        buffer[offset + 2] = UInt8((value >> 16) & 0xFF)
        buffer[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func writeUInt16LE(_ buffer: UnsafeMutableBufferPointer<UInt8>, offset: Int, value: UInt16) {
        buffer[offset] = UInt8(value & 0xFF)
        buffer[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    // MARK: - Helpers

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    enum WhisperError: LocalizedError {
        case noApiKey
        case invalidResponse
        case apiError(String)
        case noAudioData

        var errorDescription: String? {
            switch self {
            case .noApiKey: return "OpenAI API ključ ni nastavljen. Nastavite ga v nastavitvah."
            case .invalidResponse: return "Neveljaven odgovor strežnika"
            case .apiError(let msg): return msg
            case .noAudioData: return "Ni zvočnih podatkov"
            }
        }
    }
}

// MARK: - Data Multipart Extension

extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
