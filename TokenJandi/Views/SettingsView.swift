import SwiftUI

struct SettingsView: View {
    @ObservedObject var localization: LocalizationManager
    @StateObject private var updateChecker = UpdateChecker.shared
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Menu bar usage toggle
            Toggle(isOn: $showMenuBarUsage) {
                Label(L("settings.menuBarUsage"), systemImage: "menubar.rectangle")
                    .font(.caption)
            }
            .toggleStyle(.switch)

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

            // Update
            UpdateRowView(checker: updateChecker)

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
                Text("v\(UpdateChecker.currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Source
            HStack {
                Label(L("settings.source"), systemImage: "doc.text")
                    .font(.caption)
                Spacer()
                Text("~/.claude/projects/")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text(L("update.checking"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .upToDate:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(L("update.upToDate"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .available(let version):
                Button(action: { checker.performUpdate() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text("v\(version) \(L("settings.updateAvailable"))")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)

            case .downloading(let progress):
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .frame(width: 60)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

            case .installing:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text(L("update.installing"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .failed(let message):
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Button(action: { checker.checkForUpdates() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
