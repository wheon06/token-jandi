import SwiftUI

@main
struct TokenJandiApp: App {
    @StateObject private var viewModel = HeatmapViewModel()
    @StateObject private var folderAccess = FolderAccessManager()
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel, folderAccess: folderAccess)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                if showMenuBarUsage && viewModel.hasClaudeData {
                    Text(viewModel.todayUsage?.totalTokensFormatted ?? "0")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: folderAccess.hasAccess) {
            viewModel.folderAccessManager = folderAccess
            viewModel.loadData()
        }
    }
}
