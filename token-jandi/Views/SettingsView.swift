import SwiftUI

struct SettingsView: View {
    @ObservedObject var localization: LocalizationManager
    @ObservedObject var viewModel: HeatmapViewModel
    #if !APP_STORE
    @StateObject private var updateChecker = UpdateChecker.shared
    #endif
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

            Divider()

            // Update (direct distribution only)
            #if !APP_STORE
            UpdateRowView(checker: updateChecker)
            Divider()
            #endif

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
                #if APP_STORE
                Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                #else
                Text("v\(UpdateChecker.currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                #endif
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

#if !APP_STORE
struct UpdateRowView: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        HStack {
            Label(L("settings.update"), systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
            Spacer()

            switch checker.state {
            case .idle:
                Button(L("settings.checkUpdate")) { checker.checkForUpdates() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
            case .checking:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    Text(L("update.checking")).font(.caption).foregroundColor(.secondary)
                }
            case .upToDate:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                    Text(L("update.upToDate")).font(.caption).foregroundColor(.secondary)
                }
            case .available(let version):
                Button(action: { checker.performUpdate() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill").foregroundColor(.green)
                        Text("v\(version) \(L("settings.updateAvailable"))").foregroundColor(.green)
                    }.font(.caption)
                }.buttonStyle(.plain)
            case .downloading(let progress):
                HStack(spacing: 6) {
                    ProgressView(value: progress).frame(width: 60)
                    Text("\(Int(progress * 100))%").font(.caption2).foregroundColor(.secondary).monospacedDigit()
                }
            case .installing:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    Text(L("update.installing")).font(.caption).foregroundColor(.secondary)
                }
            case .failed(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.caption)
                    Text(message).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    Button(action: { checker.checkForUpdates() }) {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
#endif
