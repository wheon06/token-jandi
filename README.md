# Token Jandi


[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg?style=flat)](https://github.com/wheon06/token-jandi/blob/main/LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS-green.svg?style=flat)](https://github.com/wheon06/token-jandi)
[![Swift](https://img.shields.io/badge/Swift-5-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![CI](https://github.com/wheon06/token-jandi/actions/workflows/ci.yml/badge.svg)](https://github.com/wheon06/token-jandi/actions/workflows/ci.yml)



## Introduction

Check your Claude Code and Codex token usage easily from the macOS status bar.

## Preview 👀
![](./.github/images/preview.png)

## What's New in 1.4.1

- Codex sessions compressed in place under `sessions/` are now counted exactly instead of estimated.
- A calmer popover: three plain numbers under today's usage, no helper sentences.
- A total that includes estimated Codex threads is marked with "+"; hover it for details.
- Simpler Settings, with explanations moved into tooltips.

See [RELEASE_NOTES.md](./RELEASE_NOTES.md) for the full list.

## Data Accuracy

Token Jandi reads Claude Code and Codex usage from local files on the current Mac. Codex compresses old sessions into `~/.codex/archived_sessions` and eventually deletes the original logs; archived sessions are decoded and counted exactly, while threads that only remain in Codex's thread database are counted from their stored total and marked as an estimate in the app. If you use the same Claude or Codex account on multiple devices, usage from other devices may not appear in this app.

## Claude limits

Claude Code hands its 5-hour / 7-day usage (`rate_limits`) only to the [status line](https://code.claude.com/docs/en/statusline) script. Turn on Settings → Claude limits and Token Jandi installs a tiny bridge script (`~/.claude/token-jandi-statusline.sh`) and points `statusLine` in `~/.claude/settings.json` at it. Your previous status line keeps running after the bridge, a backup of `settings.json` is kept in `~/.claude/token-jandi/`, and turning the switch off restores the previous setting. The cards appear after the next Claude Code response. `rate_limits` is only provided on claude.ai Pro / Max plans or behind a Claude apps gateway with a spend limit.

## Requirements

- `Token Jandi` is written in Swift (Swift 5 language mode, Xcode 26)
- Compatible with macOS 14 +

## Development

```bash
xcodebuild test -project token-jandi.xcodeproj -scheme token-jandi -destination 'platform=macOS'
```

## Releasing

```bash
scripts/release.sh 1.4.1
```

Sets the version, runs the tests, uploads the Mac App Store build to App Store Connect, then tags `v1.4.1` and pushes it. The tag triggers a workflow that publishes the GitHub release from `RELEASE_NOTES.md`, so the App Store, the tag and the release always carry the same version. Write the version's section in `RELEASE_NOTES.md` and update "What's New" above first.

## Install

### Mac App Store

[Download Token Jandi on the Mac App Store](https://apps.apple.com/kr/app/token-jandi/id6761585375?mt=12)

## License 
`Token Jandi` is available under the MIT license. See the LICENSE file for more info.
