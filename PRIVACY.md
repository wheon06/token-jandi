# Privacy Policy — Token Jandi

**Last updated:** November 21, 2026

## Overview

Token Jandi is a macOS menu bar application that visualizes Claude Code and Codex token usage data stored locally on your device.

## Data Collection

**Token Jandi does not collect, transmit, or store any data on remote servers.**

- All data is read from local files on your device (`~/.claude/` and `~/.codex/`)
- No analytics, tracking, or telemetry is included
- No third-party SDKs are used
- No network requests are made except for optional update checks (direct distribution only)

## Data Access

The app reads the following local files (with your permission):
- `~/.claude/projects/*/*.jsonl` — Claude Code session logs containing token usage
- `~/.codex/sessions/**/*.jsonl` and `~/.codex/archived_sessions/*.jsonl.zst` — Codex session logs containing per-request token usage
- `~/.codex/state_*.sqlite` (read-only) — Codex's thread index, used for threads whose logs were deleted
- `~/.claude/token-jandi/statusline.json` — Claude Code rate limits, written by the optional status line bridge below
- `~/.claude.json` — Claude Code's account state. Only your plan (`organizationType` and `userRateLimitTier`) is used, to label the limits. The same file holds your email, name and organization; the app does not display, store or send them
- The `plan_type` field in Codex session logs — your Codex plan, used the same way

This data never leaves your device.

## Data Accuracy Limitation

Token Jandi calculates usage only from local Claude Code and Codex files available on the current Mac. If the same account is used on multiple devices, usage generated on other devices may be missing from Token Jandi.

## Optional: Claude limits bridge

If you turn on **Settings › Claude limits**, the app writes two things inside `~/.claude/`: a small shell script (`token-jandi-statusline.sh`) and the `statusLine` entry in `settings.json` that points Claude Code at it. Your previous status line command is preserved and keeps running, and a backup of `settings.json` is stored in `~/.claude/token-jandi/`. Turning the switch off restores the previous setting and removes the files. Nothing else in `~/.claude/` or `~/.codex/` is ever modified.

## Permissions

- **Folder Access**: The app requests access to your home folder or agent data folders via the macOS file picker. Reading is all it needs for usage data; writing is used only for the optional Claude limits bridge described above
- **Network** (direct distribution only): Used solely to check for app updates via GitHub API

## Contact

If you have questions about this privacy policy, contact:

**Heeyeon Lee**
GitHub: [@wheon06](https://github.com/wheon06)
