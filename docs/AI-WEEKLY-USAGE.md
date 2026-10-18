# Weekly usage in AI Agents

Install and enable **Dynamic Island → AI Agents**, enable Claude or Codex, and
show **Weekly usage** in its Cards settings. Each enabled provider has a weekly
card in the AI page. The card order and visibility use the existing portable
settings. Additional Codex homes retain their own Limits cards; weekly history
here refers to the default CLI source, not those added accounts.

The vertical axis is **percentage consumed, 0–100**. Remaining allowance is
100 minus consumed usage. This is a subscription quota, not context-window
occupancy, token totals, an API bill, or a forecast of future work.

- **Observed:** dots at the timestamps supplied by the existing readers. Opening
  the page or advancing its clock never adds a measurement. A later source
  measurement with the same value is still a real observation. Gaps remain gaps.
- **Original ideal:** zero to 100 at the first source-reported reset. Its start
  is inferred from the source's window duration and explicitly labeled as such;
  the zero is a planning reference, never a historical sample. Without a reported
  duration and reset this line is absent. A revised reset does not rewrite the
  original reference.
- **Recalibrated plan:** the latest consumed percentage at its observation time to
  100 at the latest source-reported reset. It is a budget, not predicted usage.
  Advancing the UI clock does not silently move this budget. It is absent once
  the last observation is ten minutes old or the reset has
  passed. The last real value, timestamp and source remain visible.
- **Daily targets:** cumulative maximum consumption along that straight line,
  with additional allowance relative to the last reading in parentheses. Targets
  use 17:00 on local weekdays and the actual reset as a final checkpoint. The
  local calendar handles weekends and daylight-saving changes; public holidays
  are not inferred. Each displayed reset includes a local date, time and zone.

A mid-cycle drop stays visible as observations and never moves the deadline.
A new source observation after the preceding reported deadline opens the next
cycle. Merely crossing a deadline never fabricates a zero, a new week, or a new
reset. Old cycles are retained locally but the quick-glance card shows the
current cycle. Account metadata is hashed locally to separate observed accounts;
switching the selected account suspends the previous plan until the new account
has a verified reading. Individual identity is required: an organization alone
does not identify a user. The card is not an account-history selector; use the
separate account Limits cards to inspect other Codex homes.

## Sources and limits

No new provider, package, authentication flow, or remote server is introduced.
The card reuses `AgentUsageService`, `AgentClaudeServer`, and `AgentCodexServer`:

- Codex's official local app-server supports `account/rateLimits/read`.
  `usedPercent` means quota consumed, `windowDurationMins` is the window length,
  and `resetsAt` is a Unix timestamp in seconds. The existing parser prefers
  `rateLimitsByLimitId.codex` to the legacy single-bucket response. While Weekly
  is visible, the existing account reader also checks the default `~/.codex`
  home, without adding it to saved account preferences. It asks only
  `account/read(refreshToken:false)` and `account/rateLimits/read`, never reset
  credits or a model turn. Checks use the existing five-minute cadence, failure
  backoff, home validation and cancellation on hide/disable/lock. No CLI
  session-log measurement is assigned to a verified account's history.
  [Official app-server reference](https://developers.openai.com/codex/app-server).
- Claude Code reports weekly consumed usage and reset times. Its public status
  line documents `rate_limits.seven_day.used_percentage` and `resets_at`, distinct
  from `context_window.used_percentage`.
  [Official status-line reference](https://code.claude.com/docs/en/statusline).
  Vorssaint reuses its existing short-lived structured `get_usage` conversation,
  including its version/failure handling; it does not install or replace a
  status-line hook. This control request is a CLI implementation interface, not
  a separately guaranteed public endpoint. The existing Claude Desktop history
  fallback has real percentages but identifies only an organization and does
  not report actual reset times. It remains available to Limits and does not
  enter this card's individual account history. Unidentified readings are not added
  to persistent history. Codex uses the email in its account response and a
  quota account ID when supplied; Claude uses its cached account UUID or email
  together with its organization. These are local digests, not exported account
  details. A CLI that omits a distinct workspace ID cannot prove isolation between
  workspaces of the same user; no cross-workspace comparison is offered.

These interfaces do not provide evidence of a scheduled, account-wide early
Codex global reset. No such scenario is displayed. Banked reset credits are a
different feature and are never consumed by this card.

This is a **local Mac collector**. It does not run with the Mac powered off,
asleep, the app stopped, or AI Agents disabled. A subsequent account reading can
include work done elsewhere, but it cannot establish when unobserved consumption
occurred. No past points are imported from the inspiration project's private
history. CLI sign-in remains managed by the installed CLIs in their own local
credential storage; this feature reads and exports no credentials or raw replies.

## Private history

Normalized observations are stored in the app's private Application Support
container at `AgentUsage/weekly-usage.json`, with owner-only directories and file
permissions. It contains provider, opaque account namespace, source, percentage,
observation/reset dates
and original cycle references. It contains no prompt, reply, account credentials
or raw provider payload, and settings export does not include it.

The history is retained across app restarts and disabling/re-enabling AI Agents,
bounded to 91 days and 40,000 observations. Disabling the feature stops adding
observations. An unreadable, invalid or unknown-version file is preserved rather
than overwritten; the card shows a warning. Restore the private file from a
backup, or move it aside while the app is stopped, to start a new history.

The visual concept is inspired by
[Usage Burndown](https://github.com/fcoalcantarajr/usage-burndown); this is a native
SwiftUI implementation using Vorssaint's existing service and feature lifecycle.
