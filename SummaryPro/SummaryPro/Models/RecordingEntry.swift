import Foundation

struct RecordingEntry: Identifiable, Codable, Hashable {
    static func == (lhs: RecordingEntry, rhs: RecordingEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: String
    let date: Date
    var transcript: String
    var language: String
    var duration: String
    var sttProvider: String
    var summary: SummaryData?
    var isMeetingMode: Bool
    var followUpEmail: String?

    init(
        id: String = Self.generateId(),
        date: Date = Date(),
        transcript: String,
        language: String,
        duration: String,
        sttProvider: String,
        summary: SummaryData? = nil,
        isMeetingMode: Bool = false,
        followUpEmail: String? = nil
    ) {
        self.id = id
        self.date = date
        self.transcript = transcript
        self.language = language
        self.duration = duration
        self.sttProvider = sttProvider
        self.summary = summary
        self.isMeetingMode = isMeetingMode
        self.followUpEmail = followUpEmail
    }

    static func generateId() -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let random = String(Int.random(in: 0..<1679616), radix: 36)
        return timestamp + random
    }
}

struct SummaryData: Codable {
    let model: String
    let modelName: String
    var summaries: [Summary]
}

struct Summary: Codable, Identifiable {
    var id: String { title }
    let title: String
    let content: String
}
