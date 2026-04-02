import SwiftUI

@main
struct TokenJandiApp: App {
    @StateObject private var viewModel = HeatmapViewModel()
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                if showMenuBarUsage {
                    Text(viewModel.todayUsage?.totalTokensFormatted ?? "0")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
