import Foundation

enum GeminiService {
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    static let summaryPrompt = """
        Si profesionalen AI asistent za povzetke sestankov in zapiskov.

        NALOGA:
        Analiziraj spodnji surovi prepis govora/zapiskov in ustvari strukturirane povzetke v slovenščini.

        PRAVILA:
        1. Ugotovi, ali prepis vsebuje ENO ali VEČ ločenih tem/sestankov/zapiskov.
        2. Za vsako ločeno temo ustvari SVOJ povzetek.
        3. Vsi povzetki MORAJO biti v SLOVENŠČINI, ne glede na jezik prepisa.
        4. Vsak povzetek naj vsebuje:
           - Jasen, kratek naslov
           - Ključne točke (bullet points)
           - Sklepe ali dogovorjene naloge (če obstajajo)
        5. Bodi jedrnat in konkreten.

        OBLIKA ODGOVORA:
        Vrni IZKLJUČNO veljaven JSON brez dodatnega besedila ali markdown ograj:
        {"summaries":[{"title":"Naslov","content":"Povzetek z markdown oblikovanjem (## naslovi, - alineje, **krepko**)"}]}

        PREPIS:
        ---
        """

    // MARK: - Fetch Available Models

    static func fetchModels(apiKey: String) async throws -> [GeminiModel] {
        let url = URL(string: "\(baseURL)/models?key=\(apiKey)")!
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeminiError.fetchModelsFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return GeminiModel.fallbackModels
        }

        let result = models.compactMap { model -> GeminiModel? in
            guard let name = model["name"] as? String else { return nil }
            let id = name.replacingOccurrences(of: "models/", with: "")

            // Filter criteria
            guard id.hasPrefix("gemini-") else { return nil }
            guard let methods = model["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent") else { return nil }

            for pattern in GeminiModel.excludedPatterns {
                if id.contains(pattern) { return nil }
            }

            let displayName = model["displayName"] as? String ?? id
            let outputLimit = model["outputTokenLimit"] as? Int ?? 8192

            return GeminiModel(
                id: id,
                name: displayName,
                generationConfig: GeminiModel.buildGenConfig(modelId: id, outputLimit: outputLimit)
            )
        }
        .sorted { GeminiModel.sortKey($0) < GeminiModel.sortKey($1) }

        return result.isEmpty ? GeminiModel.fallbackModels : result
    }

    // MARK: - Summarize

    static func summarize(
        model: GeminiModel,
        transcript: String,
        apiKey: String
    ) async throws -> [Summary] {
        let prompt = summaryPrompt + transcript + "\n---"

        var generationConfig: [String: Any] = [
            "maxOutputTokens": model.generationConfig.maxOutputTokens,
            "temperature": model.generationConfig.temperature,
        ]
        if let thinking = model.generationConfig.thinkingConfig {
            generationConfig["thinkingConfig"] = ["thinkingBudget": thinking.thinkingBudget]
        }

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]],
            ],
            "generationConfig": generationConfig,
        ]

        let url = URL(string: "\(baseURL)/models/\(model.id):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = parseErrorMessage(from: data) ?? "Gemini napaka \(httpResponse.statusCode)"
            throw GeminiError.apiError(errorMessage)
        }

        let text = extractText(from: data)
        return parseResponse(text: text)
    }

    // MARK: - Response Parsing

    private static func extractText(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            return ""
        }

        return parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
    }

    static func parseResponse(text: String) -> [Summary] {
        // Try direct JSON parse
        if let summaries = tryParseJSON(text) { return summaries }

        // Try extracting from markdown code block
        if let range = text.range(of: "```(?:json)?\\s*([\\s\\S]*?)```", options: .regularExpression) {
            let codeBlock = String(text[range])
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let summaries = tryParseJSON(codeBlock) { return summaries }
        }

        // Try finding JSON object in text
        if let range = text.range(of: "\\{[\\s\\S]*\"summaries\"[\\s\\S]*\\}", options: .regularExpression) {
            let jsonString = String(text[range])
            if let summaries = tryParseJSON(jsonString) { return summaries }
        }

        // Fallback: entire response as single summary
        return [Summary(title: "Povzetek", content: text)]
    }

    private static func tryParseJSON(_ text: String) -> [Summary]? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summariesArray = json["summaries"] as? [[String: Any]] else {
            return nil
        }

        let summaries = summariesArray.compactMap { item -> Summary? in
            guard let title = item["title"] as? String,
                  let content = item["content"] as? String else {
                return nil
            }
            return Summary(title: title, content: content)
        }

        return summaries.isEmpty ? nil : summaries
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

    enum GeminiError: LocalizedError {
        case fetchModelsFailed
        case invalidResponse
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .fetchModelsFailed: return "Napaka pri nalaganju modelov"
            case .invalidResponse: return "Neveljaven odgovor strežnika"
            case .apiError(let msg): return msg
            }
        }
    }
}
