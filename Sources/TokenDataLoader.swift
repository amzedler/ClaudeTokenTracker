import Foundation
import Combine

struct DailyUsage: Identifiable {
    let id: String // "Mon", "Tue", etc.
    let date: Date
    let cost: Double
    let tokens: Int
    let sessionCount: Int

    var label: String { id }
    var formattedCost: String { String(format: "$%.2f", cost) }
}

final class TokenDataLoader: ObservableObject {
    @Published var current: TokenData = .empty
    @Published var sessions: [TokenData] = []
    @Published var isActive: Bool = false

    private var timer: Timer?
    private let dataPath: String
    private let historyPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dataPath = "\(home)/.claude/token-usage.json"
        self.historyPath = "\(home)/.claude/token-sessions.json"
        startPolling()
    }

    func startPolling() {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.load()
        }
    }

    func load() {
        let fm = FileManager.default

        // Load current session
        if fm.fileExists(atPath: dataPath),
           let data = fm.contents(atPath: dataPath),
           let decoded = try? JSONDecoder().decode(TokenData.self, from: data) {
            DispatchQueue.main.async {
                self.current = decoded
                self.isActive = (Date().timeIntervalSince1970 - decoded.updatedAt) < 300
            }
        } else {
            DispatchQueue.main.async {
                self.isActive = false
            }
        }

        // Load session history
        if fm.fileExists(atPath: historyPath),
           let data = fm.contents(atPath: historyPath),
           let decoded = try? JSONDecoder().decode([TokenData].self, from: data) {
            DispatchQueue.main.async {
                self.sessions = decoded.reversed() // most recent first
            }
        }
    }

    /// Cost from sessions in the last 7 days (history + current)
    var trailingSevenDayCost: Double {
        let cutoff = Date().timeIntervalSince1970 - 604800
        let historyCost = sessions
            .filter { $0.updatedAt > cutoff }
            .reduce(0.0) { $0 + $1.costUsd }
        let currentCost = current.updatedAt > cutoff ? current.costUsd : 0
        return historyCost + currentCost
    }

    var formattedSevenDayCost: String {
        String(format: "$%.2f", trailingSevenDayCost)
    }

    /// Total tokens in last 7 days
    var trailingSevenDayTokens: Int {
        let cutoff = Date().timeIntervalSince1970 - 604800
        let historyTokens = sessions
            .filter { $0.updatedAt > cutoff }
            .reduce(0) { $0 + $1.totalTokens }
        let currentTokens = current.updatedAt > cutoff ? current.totalTokens : 0
        return historyTokens + currentTokens
    }

    /// Session count in last 7 days
    var trailingSevenDaySessions: Int {
        let cutoff = Date().timeIntervalSince1970 - 604800
        let count = sessions.filter { $0.updatedAt > cutoff }.count
        return count + (isActive || current.updatedAt > cutoff ? 1 : 0)
    }

    /// Daily usage aggregated for the last 7 days, one entry per day
    var dailyUsage: [DailyUsage] {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        // Collect all sessions (history + current)
        var allSessions = sessions
        if current.costUsd > 0 {
            allSessions.append(current)
        }

        // Build 7 days, newest last
        var days: [DailyUsage] = []
        for daysAgo in (0..<7).reversed() {
            guard let dayDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let startOfDay = calendar.startOfDay(for: dayDate)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { continue }

            let daySessions = allSessions.filter { session in
                let ts = Date(timeIntervalSince1970: session.updatedAt)
                return ts >= startOfDay && ts < endOfDay
            }

            let label = daysAgo == 0 ? "Today" : formatter.string(from: dayDate)
            days.append(DailyUsage(
                id: label,
                date: startOfDay,
                cost: daySessions.reduce(0.0) { $0 + $1.costUsd },
                tokens: daySessions.reduce(0) { $0 + $1.totalTokens },
                sessionCount: daySessions.count
            ))
        }
        return days
    }

    deinit {
        timer?.invalidate()
    }
}
