import SwiftUI

struct SettingsView: View {
    @ObservedObject var localization: LocalizationManager
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var folderAccess: FolderAccessManager
    @ObservedObject var bridge: ClaudeBridgeController
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayModeRaw = MenuBarDisplayMode.today.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            SectionGroup {
                SettingRow(title: L("settings.menuBarUsage")) {
                    Picker("", selection: menuBarDisplayModeBinding) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                SettingRow(title: L("settings.refreshInterval")) {
                    Picker("", selection: $viewModel.refreshIntervalRaw) {
                        ForEach(RefreshInterval.allCases) { interval in
                            Text(interval.label).tag(interval.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                SettingRow(title: L("settings.language")) {
                    Picker("", selection: $localization.selectedLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }

            SectionGroup {
                SettingRow(title: L("settings.source")) {
                    Text(folderAccess.displayPath)
                        .font(Theme.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(action: { folderAccess.requestFolderAccess() }) {
                        Image(systemName: "ellipsis.circle")
                            .font(Theme.body)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                .help(L("settings.localDataNotice"))

                if folderAccess.needsMigration {
                    HStack {
                        Text(L("settings.migrationHint"))
                            .font(Theme.caption)
                            .foregroundColor(.orange)
                        Spacer()
                        Button(L("settings.migrationAction")) { folderAccess.requestFolderAccess() }
                            .font(Theme.caption)
                            .controlSize(.small)
                    }
                }

                ClaudeBridgeRow(viewModel: viewModel, bridge: bridge, localization: localization)

            }

            // Version, privacy and quit share one quiet line.
            HStack(spacing: 10) {
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(Theme.caption)
                    .foregroundColor(.secondary)
                Button(L("settings.privacy")) {
                    if let url = URL(string: "https://github.com/wheon06/token-jandi/blob/main/PRIVACY.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(Theme.caption)
                .foregroundColor(.secondary)

                Spacer()
                Button(L("action.quit")) { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(Theme.body)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var menuBarDisplayModeBinding: Binding<MenuBarDisplayMode> {
        Binding(
            get: {
                if !showMenuBarUsage {
                    return .iconOnly
                }
                return MenuBarDisplayMode(rawValue: menuBarDisplayModeRaw) ?? .today
            },
            set: { mode in
                showMenuBarUsage = mode != .iconOnly
                menuBarDisplayModeRaw = mode.rawValue
            }
        )
    }
}

/// One switch that installs or removes the Claude status line bridge. The app
/// writes the script and rewrites `statusLine` in settings.json itself, keeping
/// the previous status line command running and a backup of the file.
struct ClaudeBridgeRow: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var bridge: ClaudeBridgeController
    @ObservedObject var localization: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingRow(title: L("settings.claudeBridge")) {
                Toggle("", isOn: Binding(
                    get: { bridge.isInstalled },
                    set: { bridge.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!bridge.isAvailable)
            }
            .help(L(bridge.isAvailable ? "settings.claudeBridge.help" : "settings.claudeBridge.notAvailable"))

            if let caption {
                Text(caption.text)
                    .font(Theme.caption)
                    .foregroundColor(caption.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { bridge.refresh() }
    }

    /// One short line under the switch, only when there is something to say.
    private var caption: (text: String, color: Color)? {
        if let errorMessage = bridge.errorMessage {
            return (errorMessage, .red)
        }
        // Connected needs no words: the switch is on and the cards are there.
        if bridge.isInstalled, viewModel.claudeRateLimitStatus == nil {
            return (L("settings.claudeBridge.waiting"), .secondary)
        }
        return nil
    }
}
