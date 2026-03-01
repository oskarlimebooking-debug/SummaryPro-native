import Foundation
import AVFoundation

enum GoogleSpeechService {
    private static let baseURL = "https://speech.googleapis.com/v1"

    static func transcribe(
        audioURL: URL,
        language: String,
        apiKey: String,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> String {
        let audioData = try Data(contentsOf: audioURL)

        // Get audio duration to decide sync vs chunked
        let asset = AVURLAsset(url: audioURL)
        let durationSeconds: Double
        if #available(iOS 16.0, *) {
            durationSeconds = try await asset.load(.duration).seconds
        } else {
            durationSeconds = asset.duration.seconds
        }

        if durationSeconds < 55 {
            onProgress(0.2, "Pošiljanje na Google Speech API...")
            return try await recognizeSync(audioData: audioData, language: language, apiKey: apiKey)
        } else {
            return try await recognizeLong(
                audioURL: audioURL,
                language: language,
                apiKey: apiKey,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Sync Recognition (<55s)

    private static func recognizeSync(audioData: Data, language: String, apiKey: String) async throws -> String {
        let base64Audio = audioData.base64EncodedString()

        let body: [String: Any] = [
            "config": [
                "encoding": "LINEAR16",
                "sampleRateHertz": 16000,
                "languageCode": language,
                "enableAutomaticPunctuation": true,
                "model": "default",
            ],
            "audio": [
                "content": base64Audio,
            ],
        ]

        let url = URL(string: "\(baseURL)/speech:recognize?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = parseErrorMessage(from: data) ?? "Speech API napaka \(httpResponse.statusCode)"
            throw SpeechError.apiError(errorMessage)
        }

        return extractTranscript(from: data)
    }

    // MARK: - Long Recognition (>55s, chunked)

    private static func recognizeLong(
        audioURL: URL,
        language: String,
        apiKey: String,
        onProgress: @escaping (Double, String) -> Void
    ) async throws -> String {
        onProgress(0.15, "Dekodiranje zvoka...")

        // Read WAV file and get PCM data
        let audioFile = try AVAudioFile(forReading: audioURL)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(audioFile.length)

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw SpeechError.noAudioData
        }

        let totalSamples = Int(buffer.frameLength)

        // Split into ~50 second chunks
        let chunkSeconds = 50
        let samplesPerChunk = Int(sampleRate) * chunkSeconds
        let totalChunks = (totalSamples + samplesPerChunk - 1) / samplesPerChunk

        var transcripts: [String] = []

        for i in 0..<totalChunks {
            let start = i * samplesPerChunk
            let end = min(start + samplesPerChunk, totalSamples)

            // Convert Float32 to LINEAR16
            let pcm16 = float32ToLinear16(channelData, offset: start, count: end - start)
            let base64Chunk = pcm16.base64EncodedString()

            let progress = 0.2 + Double(i + 1) / Double(totalChunks) * 0.35
            onProgress(progress, "Prepisovanje dela \(i + 1)/\(totalChunks)...")

            let body: [String: Any] = [
                "config": [
                    "encoding": "LINEAR16",
                    "sampleRateHertz": Int(sampleRate),
                    "languageCode": language,
                    "enableAutomaticPunctuation": true,
                    "model": "default",
                ],
                "audio": [
                    "content": base64Chunk,
                ],
            ]

            let url = URL(string: "\(baseURL)/speech:recognize?key=\(apiKey)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SpeechError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                let errorMessage = parseErrorMessage(from: data) ?? "Speech API napaka \(httpResponse.statusCode)"
                throw SpeechError.apiError(errorMessage)
            }

            let text = extractTranscript(from: data)
            if !text.isEmpty {
                transcripts.append(text)
            }
        }

        return transcripts.joined(separator: " ")
    }

    // MARK: - Helpers

    private static func float32ToLinear16(_ data: UnsafePointer<Float>, offset: Int, count: Int) -> Data {
        var result = Data(count: count * 2)
        result.withUnsafeMutableBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<count {
                let sample = max(-1.0, min(1.0, data[offset + i]))
                int16Buffer[i] = sample < 0 ? Int16(sample * 32768.0) : Int16(sample * 32767.0)
            }
        }
        return result
    }

    private static func extractTranscript(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return ""
        }

        return results.compactMap { result in
            guard let alternatives = result["alternatives"] as? [[String: Any]],
                  let transcript = alternatives.first?["transcript"] as? String else {
                return nil
            }
            return transcript
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    enum SpeechError: LocalizedError {
        case invalidResponse
        case apiError(String)
        case noAudioData

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Neveljaven odgovor strežnika"
            case .apiError(let msg): return msg
            case .noAudioData: return "Ni zvočnih podatkov"
            }
        }
    }
}
