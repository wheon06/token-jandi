# Privacy Policy — Token Jandi

**Last updated:** May 29, 2026

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
- `~/.claude/history.jsonl` — Claude Code message history
- `~/.codex/sessions/**/*.jsonl` — Codex session logs containing per-turn token usage

This data never leaves your device.

## Data Accuracy Limitation

Token Jandi calculates usage only from local Claude Code and Codex files available on the current Mac. If the same account is used on multiple devices, usage generated on other devices may be missing from Token Jandi.

## Permissions

- **Folder Access**: The app requests read-only access to your home folder or agent data folders via macOS file picker
- **Network** (direct distribution only): Used solely to check for app updates via GitHub API

## Contact

If you have questions about this privacy policy, contact:

**Heeyeon Lee**
GitHub: [@wheon06](https://github.com/wheon06)
