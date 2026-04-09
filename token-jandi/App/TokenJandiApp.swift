import SwiftUI

@main
struct TokenJandiApp: App {
    @StateObject private var viewModel = HeatmapViewModel()
    @StateObject private var folderAccess = FolderAccessManager()
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel, folderAccess: folderAccess)
                .onAppear {
                    if viewModel.folderAccessManager == nil {
                        viewModel.folderAccessManager = folderAccess
                        viewModel.loadData()
                    }
                }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                if showMenuBarUsage && viewModel.hasClaudeData {
                    Text(viewModel.allSourcesTodayUsage?.totalTokensFormatted ?? "0")
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
