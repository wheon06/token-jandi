# Release Notes

## 1.3.0 (Build 10)

- Fixed Claude Code tokens being counted roughly twice: every content block of an assistant message repeats the same usage, so responses are now counted once per `(message.id, requestId)`.
- Included Claude Code subagent logs (`projects/<project>/<session>/subagents/*.jsonl`) in all totals.
- Codex limit cards now derive their title from the reported window (for example "7d limit" for a 10080-minute window) instead of assuming 5h / 7d, and show "reset" once the window has rolled over.
- Skipped repeated Codex `token_count` events that carry no new request.
- Sandboxed builds now read the bookmarked folder on launch, so the menu bar shows usage before the popover is opened for the first time; the folder picker opens in the real home folder.
- Re-selecting the data folder reloads immediately.
- Refreshes only re-parse log files whose size or modification time changed.
- "Today" rolls over at midnight even with auto refresh off, and the streak keeps counting until today's first usage arrives.
- Monthly chart now sums whole calendar months; "This week" was renamed to "Last 7 days" to match what it shows.
- Localized strings now live only in `Localizable.strings`; added unit tests and a CI workflow.

## 1.2.0 (Build 7)

- Improved Codex token accuracy by using full turn totals.
- Added Codex 5-hour and 7-day limit usage cards with reset times.
- Added a notice that usage is based on local files from the current Mac, so multi-device account usage may be incomplete.
- Fixed an unsupported SF Symbol used in the empty state.
