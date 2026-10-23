import SwiftUI

@main
struct TokenJandiApp: App {
    @StateObject private var folderAccess: FolderAccessManager
    @StateObject private var viewModel: UsageViewModel
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayModeRaw = MenuBarDisplayMode.today.rawValue

    init() {
        // Folder access must exist before the first load so the sandboxed app reads
        // the bookmarked folder instead of its own container.
        let folderAccess = FolderAccessManager()
        _folderAccess = StateObject(wrappedValue: folderAccess)
        _viewModel = StateObject(wrappedValue: UsageViewModel(folderAccess: folderAccess))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel, folderAccess: folderAccess)
                .onAppear {
                    // Cheap when nothing changed: only file metadata is compared.
                    viewModel.loadData()
                }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                if let menuBarText {
                    Text(menuBarText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarDisplayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: menuBarDisplayModeRaw) ?? .today
    }

    private var menuBarText: String? {
        guard showMenuBarUsage, viewModel.hasUsageData else { return nil }

        switch menuBarDisplayMode {
        case .today:
            return formatTokenCount(viewModel.todayTokens(for: .all))
        case .thisWeek:
            return formatTokenCount(viewModel.last7DaysTokens(for: .all))
        case .claudeToday:
            return formatTokenCount(viewModel.todayTokens(for: .claude))
        case .codexToday:
            return formatTokenCount(viewModel.todayTokens(for: .codex))
        case .iconOnly:
            return nil
        }
    }
}
