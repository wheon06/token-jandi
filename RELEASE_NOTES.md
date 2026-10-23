# Release Notes

## 1.4.0 (Build 10)

- Counted Codex sessions that Codex has archived (`archived_sessions/*.jsonl.zst`, decoded with zstd) and, for threads whose rollout file was deleted, their totals from Codex's thread database (`state_<n>.sqlite`). Those database-only threads are attributed to the day the thread started and flagged in the app as a possible undercount.
- Fixed Claude Code tokens being counted roughly twice: every content block of an assistant message repeats the same usage, so responses are now counted once per `(message.id, requestId)`.
- Included Claude Code subagent logs (`projects/<project>/<session>/subagents/*.jsonl`) in all totals.
- Added Claude 5h / 7d limit cards (and the Claude apps gateway spend limit). Claude Code reports its limits only to the status line, so a switch in Settings › Claude limits installs a small bridge script and points `statusLine` in `~/.claude/settings.json` at it, keeping the previous status line running and a backup of the file; turning it off restores the previous setting. The folder permission is now read-write for this; users who picked their folder with an older version are asked to pick it again the first time they turn the switch on. Pro / Max plans only.
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
