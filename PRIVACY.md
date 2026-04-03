# Privacy Policy — Token Jandi

**Last updated:** April 3, 2026

## Overview

Token Jandi is a macOS menu bar application that visualizes Claude Code token usage data stored locally on your device.

## Data Collection

**Token Jandi does not collect, transmit, or store any data on remote servers.**

- All data is read from local files on your device (`~/.claude/projects/`)
- No analytics, tracking, or telemetry is included
- No third-party SDKs are used
- No network requests are made except for optional update checks (direct distribution only)

## Data Access

The app reads the following local files (with your permission):
- `~/.claude/projects/*/*.jsonl` — Claude Code session logs containing token usage
- `~/.claude/history.jsonl` — Claude Code message history

This data never leaves your device.

## Permissions

- **Folder Access**: The app requests read-only access to your `.claude` folder via macOS file picker
- **Network** (direct distribution only): Used solely to check for app updates via GitHub API

## Contact

If you have questions about this privacy policy, contact:

**Heeyeon Lee**
GitHub: [@wheon06](https://github.com/wheon06)
