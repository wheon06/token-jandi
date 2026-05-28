import SwiftUI

struct SettingsView: View {
    @ObservedObject var localization: LocalizationManager
    @ObservedObject var viewModel: HeatmapViewModel
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Menu bar usage toggle
            Toggle(isOn: $showMenuBarUsage) {
                Label(L("settings.menuBarUsage"), systemImage: "menubar.rectangle")
                    .font(.caption)
            }
            .toggleStyle(.switch)

            // Auto refresh interval
            HStack {
                Label(L("settings.refreshInterval"), systemImage: "arrow.clockwise")
                    .font(.caption)
                Spacer()
                Picker("", selection: $viewModel.refreshIntervalRaw) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }

            Divider()

            // Language
            HStack {
                Label(L("settings.language"), systemImage: "globe")
                    .font(.caption)
                Spacer()
                Picker("", selection: $localization.selectedLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            Divider()

            // Data source / folder
            HStack {
                Label(L("settings.source"), systemImage: "folder")
                    .font(.caption)
                Spacer()
                if let url = viewModel.folderAccessManager?.claudeDirectoryURL {
                    Text(url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("~/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button(action: { viewModel.folderAccessManager?.requestFolderAccess() }) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }

            if viewModel.folderAccessManager?.needsMigration == true {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text(L("settings.migrationHint"))
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Spacer()
                    Button(L("settings.migrationAction")) {
                        viewModel.folderAccessManager?.requestFolderAccess()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }

            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 1)

                Text(L("settings.localDataNotice"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Author
            HStack {
                Label(L("settings.author"), systemImage: "person")
                    .font(.caption)
                Spacer()
                Text("Heeyeon Lee")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Version
            HStack {
                Label(L("settings.version"), systemImage: "info.circle")
                    .font(.caption)
                Spacer()
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Privacy Policy
            HStack {
                Label(L("settings.privacy"), systemImage: "hand.raised")
                    .font(.caption)
                Spacer()
                Button(action: {
                    if let url = URL(string: "https://github.com/wheon06/token-jandi/blob/main/PRIVACY.md") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Quit
            HStack {
                Spacer()
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text(L("action.quit"))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
