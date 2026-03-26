import Foundation

struct TokenData: Codable {
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheRead: Int
    let cacheWrite: Int
    let costUsd: Double
    let durationMs: Int
    let apiDurationMs: Int
    let contextPct: Double
    let contextSize: Int
    let updatedAt: Double
    var sessionStarted: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case costUsd = "cost_usd"
        case durationMs = "duration_ms"
        case apiDurationMs = "api_duration_ms"
        case contextPct = "context_pct"
        case contextSize = "context_size"
        case updatedAt = "updated_at"
        case sessionStarted = "session_started"
    }

    var totalTokens: Int { inputTokens + outputTokens }

    var formattedCost: String { String(format: "$%.2f", costUsd) }
    var formattedInputTokens: String { Self.formatTokens(inputTokens) }
    var formattedOutputTokens: String { Self.formatTokens(outputTokens) }
    var formattedCacheRead: String { Self.formatTokens(cacheRead) }
    var formattedCacheWrite: String { Self.formatTokens(cacheWrite) }
    var formattedTotalTokens: String { Self.formatTokens(totalTokens) }

    var formattedDuration: String {
        let totalSec = durationMs / 1000
        let mins = totalSec / 60
        let secs = totalSec % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }

    var formattedApiDuration: String {
        let totalSec = apiDurationMs / 1000
        let mins = totalSec / 60
        let secs = totalSec % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }

    var contextPercentInt: Int { Int(contextPct) }
    var formattedContextSize: String { Self.formatTokens(contextSize) }

    var sessionDate: Date {
        Date(timeIntervalSince1970: sessionStarted ?? updatedAt)
    }

    var formattedSessionDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(sessionDate) {
            formatter.dateFormat = "h:mm a"
            return "Today \(formatter.string(from: sessionDate))"
        } else if calendar.isDateInYesterday(sessionDate) {
            formatter.dateFormat = "h:mm a"
            return "Yesterday \(formatter.string(from: sessionDate))"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: sessionDate)
        }
    }

    var timeSinceUpdate: String {
        let elapsed = Date().timeIntervalSince1970 - updatedAt
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }

    static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    static let empty = TokenData(
        model: "—", inputTokens: 0, outputTokens: 0,
        cacheRead: 0, cacheWrite: 0, costUsd: 0,
        durationMs: 0, apiDurationMs: 0, contextPct: 0,
        contextSize: 0, updatedAt: 0, sessionStarted: 0
    )
}
