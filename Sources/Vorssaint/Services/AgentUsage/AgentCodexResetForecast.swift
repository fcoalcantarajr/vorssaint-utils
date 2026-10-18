// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A public historical estimate, kept outside all private quota history.
struct AgentCodexResetForecast {
    let estimatedReset: Date
    let resetCount: Int
    let generatedAt: Date
    let fetchedAt: Date
    let expiresAt: Date
    static let source = URL(string: "https://codex-resets.com")!
    static let endpoint = URL(string: "https://codex-resets.com/api/v1/resets?limit=100")!
    static let maximumSize = 256 << 10

    private struct Feed: Decodable {
        struct Reset: Decodable { let resetType: String; let announcedAt: String }
        struct Meta: Decodable { let apiVersion: String; let generatedAt: String }
        let data: [Reset]
        let meta: Meta
    }

    static func decode(_ data: Data, fetchedAt: Date) -> Self? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard data.count <= maximumSize, let feed = try? decoder.decode(Feed.self, from: data),
              feed.meta.apiVersion == "v1", feed.data.count <= 100,
              let generated = date(feed.meta.generatedAt), generated <= fetchedAt,
              fetchedAt.timeIntervalSince(generated) < 86_400 else { return nil }
        var dates = Set<Date>()
        for reset in feed.data {
            guard ["regular", "banked"].contains(reset.resetType),
                  let announced = date(reset.announcedAt), announced <= generated,
                  announced.timeIntervalSince1970 > 0 else { return nil }
            if reset.resetType == "regular" { dates.insert(announced) }
        }
        let ordered = dates.sorted()
        guard ordered.count >= 3, let first = ordered.first, let last = ordered.last else { return nil }
        // The sum of consecutive intervals is last − first. Credits and
        // duplicate announcements cannot distort this arithmetic mean.
        let interval = last.timeIntervalSince(first) / Double(ordered.count - 1)
        let estimate = last.addingTimeInterval(interval)
        guard interval > 0, estimate > fetchedAt else { return nil }
        return Self(estimatedReset: estimate, resetCount: ordered.count, generatedAt: generated,
                    fetchedAt: fetchedAt, expiresAt: min(estimate, generated.addingTimeInterval(86_400)))
    }

    func plan(provider: AgentProvider, sample: AgentWeeklyUsage.Sample, now: Date) -> AgentWeeklyPlan? {
        guard provider == .codex, now >= fetchedAt, now < expiresAt,
              let actual = sample.resetsAt, estimatedReset < actual else { return nil }
        return AgentWeeklyPlan(sample: sample, now: now, speculativeReset: estimatedReset)
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: text) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
