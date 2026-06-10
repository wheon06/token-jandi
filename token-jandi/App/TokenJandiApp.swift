import SwiftUI

@main
struct TokenJandiApp: App {
    @StateObject private var viewModel = HeatmapViewModel()
    @StateObject private var folderAccess = FolderAccessManager()
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayModeRaw = MenuBarDisplayMode.today.rawValue

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel, folderAccess: folderAccess)
                .onAppear {
                    if viewModel.folderAccessManager == nil {
                        viewModel.folderAccessManager = folderAccess
                        viewModel.loadData(force: true)
                    }
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
        .onChange(of: folderAccess.hasAccess) {
            viewModel.folderAccessManager = folderAccess
            viewModel.loadData(force: true)
        }
    }

    private var menuBarDisplayMode: MenuBarDisplayMode {
        MenuBarDisplayMode(rawValue: menuBarDisplayModeRaw) ?? .today
    }

    private var menuBarText: String? {
        guard showMenuBarUsage, viewModel.hasClaudeData else { return nil }

        switch menuBarDisplayMode {
        case .today:
            return viewModel.allSourcesTodayUsage?.totalTokensFormatted ?? "0"
        case .thisWeek:
            return formatTokenCount(viewModel.weeklyTokens)
        case .claudeToday:
            return formatTokenCount(viewModel.todayTokens(for: .claude))
        case .codexToday:
            return formatTokenCount(viewModel.todayTokens(for: .codex))
        case .iconOnly:
            return nil
        }
    }
}
