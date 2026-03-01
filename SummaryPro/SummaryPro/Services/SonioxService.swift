import Foundation
import AVFoundation

enum SonioxService {
    private static let baseURL = "https://api.soniox.com/v1"

    static func transcribe(
        audioURL: URL,
        language: String,
        apiKey: String,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw SonioxError.noApiKey
        }

        let languageCode = language.components(separatedBy: "-").first ?? language

        // Convert to WAV for compatibility
        onProgress(0.15, "Pretvarjanje zvoka...")
        let wavData = try createWAVFromFile(url: audioURL)

        // Step 1: Upload audio file
        onProgress(0.2, "Nalaganje zvoka na Soniox...")
        let fileId = try await uploadFile(wavData: wavData, apiKey: apiKey)

        do {
            // Step 2: Create async transcription
            onProgress(0.25, "Ustvarjanje transkripcije...")
            let jobId = try await createTranscription(fileId: fileId, language: languageCode, apiKey: apiKey)

            // Step 3: Poll until completed
            var status = "queued"
            while status == "queued" || status == "processing" {
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                onProgress(0.35, "Čakanje na transkripcijo...")
                let pollResult = try await pollTranscription(jobId: jobId, apiKey: apiKey)
                status = pollResult.status
                if status == "error" {
                    throw SonioxError.apiError(pollResult.errorMessage ?? "Soniox transkripcija ni uspela")
                }
            }

            // Step 4: Get transcript text
            onProgress(0.5, "Pridobivanje prepisa...")
            let transcript = try await getTranscript(jobId: jobId, apiKey: apiKey)

            // Cleanup (fire-and-forget)
            Task {
                try? await deleteResource(path: "/transcriptions/\(jobId)", apiKey: apiKey)
                try? await deleteResource(path: "/files/\(fileId)", apiKey: apiKey)
            }

            return transcript

        } catch {
            // Cleanup file on error (fire-and-forget)
            Task {
                try? await deleteResource(path: "/files/\(fileId)", apiKey: apiKey)
            }
            throw error
        }
    }

    // MARK: - API Calls

    private static func uploadFile(wavData: Data, apiKey: String) async throws -> String {
        let boundary = UUID().uuidString
        var body = Data()
        body.appendMultipart(boundary: boundary, name: "file", filename: "audio.wav", mimeType: "audio/wav", data: wavData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: "\(baseURL)/files")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw SonioxError.invalidResponse
        }

        return id
    }

    private static func createTranscription(fileId: String, language: String, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "model": "stt-async-preview",
            "file_id": fileId,
            "language_hints": [language],
        ]

        let url = URL(string: "\(baseURL)/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw SonioxError.invalidResponse
        }

        return id
    }

    private struct PollResult {
        let status: String
        let errorMessage: String?
    }

    private static func pollTranscription(jobId: String, apiKey: String) async throws -> PollResult {
        let url = URL(string: "\(baseURL)/transcriptions/\(jobId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw SonioxError.invalidResponse
        }

        return PollResult(status: status, errorMessage: json["error_message"] as? String)
    }

    private static func getTranscript(jobId: String, apiKey: String) async throws -> String {
        let url = URL(string: "\(baseURL)/transcriptions/\(jobId)/transcript")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw SonioxError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deleteResource(path: String, apiKey: String) async throws {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - WAV Conversion

    private static func createWAVFromFile(url: URL) throws -> Data {
        let audioFile = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let frameCount = AVAudioFrameCount(audioFile.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount)!
        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw SonioxError.noAudioData
        }

        let totalSamples = Int(buffer.frameLength)

        // Resample to 16kHz if needed
        let sourceSampleRate = audioFile.processingFormat.sampleRate
        let targetSampleRate = 16000.0
        let resampledCount: Int
        let samples: [Float]

        if abs(sourceSampleRate - targetSampleRate) < 1.0 {
            resampledCount = totalSamples
            samples = Array(UnsafeBufferPointer(start: channelData, count: totalSamples))
        } else {
            let ratio = targetSampleRate / sourceSampleRate
            resampledCount = Int(Double(totalSamples) * ratio)
            samples = (0..<resampledCount).map { i in
                let sourceIndex = Double(i) / ratio
                let index = Int(sourceIndex)
                let fraction = Float(sourceIndex - Double(index))
                if index + 1 < totalSamples {
                    return channelData[index] * (1.0 - fraction) + channelData[index + 1] * fraction
                }
                return channelData[min(index, totalSamples - 1)]
            }
        }

        // Build WAV
        let numChannels = 1
        let bytesPerSample = 2
        let dataLength = resampledCount * numChannels * bytesPerSample
        let headerSize = 44

        var wavData = Data(count: headerSize + dataLength)
        wavData.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)

            func writeStr(_ offset: Int, _ str: String) {
                for (i, ch) in str.utf8.enumerated() { bytes[offset + i] = ch }
            }
            func writeU32(_ offset: Int, _ val: UInt32) {
                bytes[offset] = UInt8(val & 0xFF)
                bytes[offset+1] = UInt8((val >> 8) & 0xFF)
                bytes[offset+2] = UInt8((val >> 16) & 0xFF)
                bytes[offset+3] = UInt8((val >> 24) & 0xFF)
            }
            func writeU16(_ offset: Int, _ val: UInt16) {
                bytes[offset] = UInt8(val & 0xFF)
                bytes[offset+1] = UInt8((val >> 8) & 0xFF)
            }

            writeStr(0, "RIFF")
            writeU32(4, UInt32(36 + dataLength))
            writeStr(8, "WAVE")
            writeStr(12, "fmt ")
            writeU32(16, 16)
            writeU16(20, 1)
            writeU16(22, UInt16(numChannels))
            writeU32(24, UInt32(targetSampleRate))
            writeU32(28, UInt32(targetSampleRate) * UInt32(numChannels * bytesPerSample))
            writeU16(32, UInt16(numChannels * bytesPerSample))
            writeU16(34, 16)
            writeStr(36, "data")
            writeU32(40, UInt32(dataLength))

            let int16Ptr = UnsafeMutableRawPointer(bytes.baseAddress! + headerSize)
                .bindMemory(to: Int16.self, capacity: resampledCount)
            for i in 0..<resampledCount {
                let s = max(-1.0, min(1.0, samples[i]))
                int16Ptr[i] = s < 0 ? Int16(s * 32768.0) : Int16(s * 32767.0)
            }
        }

        return wavData
    }

    // MARK: - Helpers

    private static func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SonioxError.invalidResponse
        }
        if httpResponse.statusCode == 204 { return }
        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            let message = parseErrorMessage(from: data) ?? "Soniox napaka \(httpResponse.statusCode)"
            throw SonioxError.apiError(message)
        }
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["message"] as? String
    }

    enum SonioxError: LocalizedError {
        case noApiKey
        case invalidResponse
        case apiError(String)
        case noAudioData

        var errorDescription: String? {
            switch self {
            case .noApiKey: return "Soniox API ključ ni nastavljen. Nastavite ga v nastavitvah."
            case .invalidResponse: return "Neveljaven odgovor strežnika"
            case .apiError(let msg): return msg
            case .noAudioData: return "Ni zvočnih podatkov"
            }
        }
    }
}
