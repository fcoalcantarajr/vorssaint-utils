// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentWeeklyUsageTests {
    static func run(_ suite: TestSuite) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = start.addingTimeInterval(604_800)
        func reading(_ percent: Double, at date: Date, reset end: Date? = reset,
                     source: AgentLimits.Source = .account, account: String? = "account-a") -> AgentLimits {
            AgentLimits(provider: .codex, windows: [
                AgentLimitWindow(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                                 usedPercent: percent, resetsAt: end)
            ], observedAt: date, source: source, accountScope: account)
        }
        var history = AgentWeeklyUsage()
        var isolated = AgentWeeklyUsage()
        _ = isolated.record(reading(20, at: start), now: start)
        _ = isolated.record(reading(70, at: start.addingTimeInterval(60), reset: reset.addingTimeInterval(3600), account: "account-b"),
                            now: start.addingTimeInterval(60))
        suite.expect(isolated.cycles.count == 2 && isolated.current(.codex)?.originalReset == reset.addingTimeInterval(3600),
                     "switching accounts isolates history and the original baseline even before the old deadline")
        suite.expect(!isolated.record(reading(75, at: start.addingTimeInterval(120), account: nil), now: start.addingTimeInterval(120)),
                     "a session log without account identity cannot contaminate a verified account history")
        isolated.selectAccount(nil, provider: .codex)
        suite.expect(isolated.current(.codex) == nil && isolated.cycles.count == 2,
                     "losing account verification immediately removes the old plan without deleting its history")
        let opaque = AgentWeeklyAccount.scope(identifier: "person@example.invalid", organization: "org-a")
        suite.expect(opaque?.count == 64 && opaque != AgentWeeklyAccount.scope(identifier: "person@example.invalid", organization: "org-b")
                     && AgentWeeklyAccount.scope(identifier: nil, organization: "org-a") == nil,
                     "account namespaces contain only a digest, distinguish organizations, and require individual identity")
        suite.expect(history.record(reading(25, at: start), now: start), "a genuine weekly observation is saved")
        suite.expect(!history.record(reading(25, at: start), now: start), "the same source observation is not sampled again on a UI tick")
        suite.expect(history.record(reading(25, at: start.addingTimeInterval(60)), now: start.addingTimeInterval(60)),
                     "a later real observation with unchanged consumption is retained")
        suite.expect(!history.record(reading(90, at: start.addingTimeInterval(-60)), now: start),
                     "an old log cannot overwrite a newer account reading")
        suite.expect(!history.record(reading(.nan, at: start.addingTimeInterval(120)), now: start.addingTimeInterval(120)),
                     "non-finite consumption is rejected")
        suite.expect(!history.record(reading(101, at: start.addingTimeInterval(120)), now: start.addingTimeInterval(120)),
                     "out-of-range consumption is not silently turned into a measurement")
        suite.expect(!history.record(reading(50, at: reset), now: start), "future observations are rejected")
        let changedReset = reset.addingTimeInterval(-3600)
        _ = history.record(reading(40, at: start.addingTimeInterval(120), reset: changedReset), now: start.addingTimeInterval(120))
        let cycle = history.current(.codex)!
        suite.expect(cycle.originalReset == reset && cycle.latest?.resetsAt == changedReset,
                     "a changed provider deadline updates the plan while preserving the original reference")
        _ = history.record(reading(5, at: start.addingTimeInterval(180), reset: changedReset), now: start.addingTimeInterval(180))
        suite.expect(history.cycles.count == 1 && history.current(.codex)?.samples.count == 4,
                     "a mid-cycle allowance refill keeps real samples and never moves the weekly deadline")
        let plan = AgentWeeklyPlan(sample: cycle.latest!, now: start.addingTimeInterval(120))!
        let laterPlan = AgentWeeklyPlan(sample: cycle.latest!, now: start.addingTimeInterval(180))!
        suite.expect(laterPlan.start == plan.start && laterPlan.used(at: start.addingTimeInterval(3600)) == plan.used(at: start.addingTimeInterval(3600)),
                     "a UI tick cannot move a budget without a new source observation")
        suite.expect(plan.remainingPercent == 60 && plan.used(at: changedReset) == 100 && plan.used(at: plan.start) == 40,
                     "the linear plan starts at consumed usage and spends exactly the remaining allowance at the actual reset")
        suite.expect(AgentWeeklyPlan(sample: cycle.latest!, now: changedReset) == nil,
                     "crossing the deadline cannot invent the next cycle or zero usage")
        suite.expect(AgentWeeklyPlan(sample: cycle.latest!, now: start.addingTimeInterval(1000)) == nil,
                     "stale observations remain history without a purported current budget")
        _ = history.record(reading(2, at: reset.addingTimeInterval(60), reset: reset.addingTimeInterval(604_800)),
                           now: reset.addingTimeInterval(60))
        suite.expect(history.cycles.count == 2, "only a source observation beyond the deadline opens the next cycle")

        var desktop = AgentWeeklyUsage()
        suite.expect(!desktop.record(reading(30, at: start, source: .claudeApp), now: start) && desktop.cycles.isEmpty,
                     "organization-only desktop readings cannot be assigned to an individual Code account")
        var unknown = AgentWeeklyUsage()
        _ = unknown.record(reading(30, at: start, reset: nil), now: start)
        suite.expect(unknown.current(.codex)!.latest!.isStale(at: start.addingTimeInterval(600)),
                     "an observation becomes stale even when no reset was reported")
        suite.expect(AgentWeeklyPlan(sample: unknown.current(.codex)!.latest!, now: start) == nil,
                     "an unknown reset means no invented ideal or budget")
        persistence(suite, history: history)
        checkpoints(suite)
        for language in AppLanguage.allCases {
            let strings = AgentWeeklyStrings.localized(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(values.count == 21 && values.allSatisfy { !$0.isEmpty }
                         && strings.title == FeatureStrings.notchAgents(language).card(.weekly),
                         "weekly usage is localized consistently for \(language.rawValue)")
        }
    }

    private static func persistence(_ suite: TestSuite, history: AgentWeeklyUsage) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("weekly.json")
        suite.expect(AgentWeeklyUsageFile.save(history, to: url), "normalized history saves in a private local file")
        let loaded = AgentWeeklyUsageFile.load(from: url)
        suite.expect(loaded.history == history && !loaded.failed, "all genuine points and original deadlines survive restart")
        let mode = (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber
        suite.expect(mode?.intValue == 0o600, "weekly history is owner-only")
        let bytes = (try? Data(contentsOf: url)) ?? Data()
        let text = String(decoding: bytes, as: UTF8.self)
        suite.expect(!text.contains("access_token") && !text.contains("session_id"), "history contains normalized quota observations only")
        try? Data("broken history".utf8).write(to: url)
        let invalid = AgentWeeklyUsageFile.load(from: url)
        suite.expect(invalid.failed && invalid.history == AgentWeeklyUsage(), "corrupt history is reported instead of treated as an empty valid file")
        suite.expect(!AgentWeeklyUsageFile.save(history, to: url) && (try? Data(contentsOf: url)) == Data("broken history".utf8),
                     "subsequent collection cannot overwrite a damaged history file")
    }

    private static func checkpoints(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let parse = ISO8601DateFormatter()
        // Friday before the spring DST change, through Tuesday after it.
        let now = parse.date(from: "2026-03-06T23:00:00Z")!
        let reset = parse.date(from: "2026-03-10T20:00:00Z")!
        let sample = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40, resetsAt: reset, source: "account")
        let plan = AgentWeeklyPlan(sample: sample, now: now)!
        let goals = plan.checkpoints(calendar: calendar)
        suite.expect(goals.count == 2 && goals.first?.date == parse.date(from: "2026-03-09T21:00:00Z") && goals.last?.date == reset,
                     "daily checkpoints skip weekends, follow local DST at 17:00, and end at the actual reset")
        suite.expect(abs((goals.first?.usedPercent ?? 0) - 85.16129032258064) < 0.000001,
                     "daily targets use elapsed time on the recalibrated line, in percentage points")
        suite.expect(goals.last?.usedPercent == 100, "the final checkpoint uses the complete quota")
        let nearCheckpoint = parse.date(from: "2026-03-09T21:00:30Z")!
        let nearSample = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40,
                                                 resetsAt: nearCheckpoint, source: "account")
        let nearGoals = AgentWeeklyPlan(sample: nearSample, now: now)!.checkpoints(calendar: calendar)
        suite.expect(nearGoals.count == 1 && nearGoals.first?.date == nearCheckpoint
                     && nearGoals.first?.usedPercent == 100,
                     "a reset within the 17:00 display minute replaces the daily checkpoint without changing its actual deadline")
    }
}
