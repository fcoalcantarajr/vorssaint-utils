// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentCodexResetForecastTests {
    static func run(_ suite: TestSuite) {
        let parse = ISO8601DateFormatter()
        let now = parse.date(from: "2026-10-18T12:00:00Z")!
        // Regular intervals are 4 and 6 days. The banked credit must not
        // shorten their five-day mean or become the forecast's anchor.
        let body = #"{"data":[{"reset_type":"regular","announced_at":"2026-10-07T10:00:00.000Z"},{"reset_type":"regular","announced_at":"2026-10-11T10:00:00Z"},{"reset_type":"regular","announced_at":"2026-10-17T10:00:00Z"},{"reset_type":"banked","announced_at":"2026-10-18T11:00:00Z"}],"pagination":{"has_more":false,"next_cursor":null},"meta":{"api_version":"v1","generated_at":"2026-10-18T11:59:00.000Z"}}"#
        guard let forecast = AgentCodexResetForecast.decode(Data(body.utf8), fetchedAt: now) else {
            suite.expect(false, "a real public reset feed supplies a speculative deadline")
            return
        }
        let deadline = parse.date(from: "2026-10-22T10:00:00Z")!
        suite.expect(forecast.estimatedReset == deadline && forecast.resetCount == 3,
                     "the historical mean uses distinct executed regular resets, never banked credits")
        let actual = parse.date(from: "2026-10-25T12:00:00Z")!
        let sample = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40, resetsAt: actual, source: "account")
        let scenario = forecast.plan(provider: .codex, sample: sample, now: now)
        suite.expect(scenario?.reset == deadline && scenario?.used(at: deadline) == 100
                     && scenario?.used(at: now) == 40,
                     "the speculative line spends remaining quota from a real reading to its own deadline")
        suite.expect(AgentWeeklyPlan(sample: sample, now: now)?.reset == actual && sample.resetsAt == actual,
                     "the actual account reset and normal budget remain independent of speculation")
        suite.expect(forecast.plan(provider: .claude, sample: sample, now: now) == nil,
                     "a public Codex reset never produces a Claude scenario")
        let sooner = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40,
                                              resetsAt: deadline.addingTimeInterval(-60), source: "account")
        suite.expect(forecast.plan(provider: .codex, sample: sooner, now: now) == nil,
                     "an estimate later than the real quota reset is not an early-reset line")
        let unknown = AgentWeeklyUsage.Sample(observedAt: now, usedPercent: 40, resetsAt: nil, source: "account")
        suite.expect(forecast.plan(provider: .codex, sample: unknown, now: now) == nil,
                     "speculation cannot substitute for a missing account deadline")
        suite.expect(forecast.plan(provider: .codex, sample: sample, now: now.addingTimeInterval(600)) == nil,
                     "stale account observations cannot anchor speculative budgets")
        let expiredNow = now.addingTimeInterval(86_400)
        let fresh = AgentWeeklyUsage.Sample(observedAt: expiredNow, usedPercent: 40, resetsAt: actual, source: "account")
        suite.expect(forecast.plan(provider: .codex, sample: fresh, now: expiredNow) == nil,
                     "a forecast expires within 24 hours even with a fresh account reading")
        let atDeadline = AgentWeeklyUsage.Sample(observedAt: deadline, usedPercent: 40, resetsAt: actual, source: "account")
        suite.expect(forecast.plan(provider: .codex, sample: atDeadline, now: deadline) == nil,
                     "passing the estimated reset never rolls speculation forward or invents a refill")
        for changed in [body.replacingOccurrences(of: "v1", with: "v2"),
                        body.replacingOccurrences(of: "2026-10-17T10:00:00Z", with: "2026-10-19T10:00:00Z"),
                        body.replacingOccurrences(of: "2026-10-11T10:00:00Z", with: "invalid"),
                        body.replacingOccurrences(of: "2026-10-18T11:59:00.000Z", with: "2026-10-16T12:00:00Z") ] {
            suite.expect(AgentCodexResetForecast.decode(Data(changed.utf8), fetchedAt: now) == nil,
                         "unknown, future, malformed or old source data supplies no scenario")
        }
        let onlyCredits = body.replacingOccurrences(of: "regular", with: "banked")
        suite.expect(AgentCodexResetForecast.decode(Data(onlyCredits.utf8), fetchedAt: now) == nil,
                     "banked credits alone are not evidence of an automatic global reset")
        source(suite, body: Data(body.utf8), now: now)
    }

    private static func source(_ suite: TestSuite, body: Data, now: Date) {
        var clock = now
        var callbacks: [(Data?) -> Void] = []
        var cancellations = 0
        let source = AgentCodexResetForecastSource(loader: { completion in
            callbacks.append(completion)
            return { cancellations += 1 }
        }, clock: { clock })
        source.synchronize(enabled: false)
        suite.expect(callbacks.isEmpty, "a hidden or disabled speculative card makes no public request")
        source.synchronize(enabled: true)
        source.synchronize(enabled: true)
        guard callbacks.count == 1 else {
            suite.expect(false, "a visible speculative card starts one bounded public request")
            return
        }
        source.synchronize(enabled: false)
        callbacks[0](body)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        suite.expect(cancellations == 1 && source.forecast == nil,
                     "hiding cancels the public request and ignores its late completion")
        source.synchronize(enabled: true)
        guard callbacks.count == 2 else {
            suite.expect(false, "a cancelled request can retry when the card returns")
            return
        }
        callbacks[1](body)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        suite.expect(source.forecast?.resetCount == 3, "a successful public response reaches the actual forecast state")
        source.synchronize(enabled: true)
        suite.expect(callbacks.count == 2, "UI ticks do not repeatedly fetch a fresh public history")
        clock = now.addingTimeInterval(6 * 3600)
        source.synchronize(enabled: true)
        guard callbacks.count == 3 else {
            suite.expect(false, "an open card checks the public history again after six hours")
            return
        }
        callbacks[2](nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        source.synchronize(enabled: true)
        suite.expect(source.forecast?.resetCount == 3 && callbacks.count == 3,
                     "a download failure retains the expiring estimate and backs off instead of retrying every tick")
    }
}
