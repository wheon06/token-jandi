import SwiftUI

@main
struct TokenJandiApp: App {
    @StateObject private var viewModel = HeatmapViewModel()
    @StateObject private var folderAccess = FolderAccessManager()
    @ObservedObject private var usageService = AnthropicUsageService.shared
    @AppStorage("showMenuBarUsage") private var showMenuBarUsage = true

    private var isPercentageMode: Bool {
        viewModel.displayMode == .percentage
    }

    private var displayRatio: Double {
        usageService.usageRatio
    }

    private var displayText: String {
        if isPercentageMode {
            return formatPercent(displayRatio)
        }
        return viewModel.todayUsage?.totalTokensFormatted ?? "0"
    }

    private var hasData: Bool {
        isPercentageMode ? usageService.hasCredentials : viewModel.hasClaudeData
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel, folderAccess: folderAccess, usageService: usageService)
        } label: {
            HStack(spacing: 5) {
                MenuBarIconView(
                    ratio: displayRatio,
                    hasData: hasData,
                    isPercentageMode: isPercentageMode
                )
                if showMenuBarUsage && hasData {
                    Text(displayText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar icon with a circular progress ring around the leaf
struct MenuBarIconView: View {
    let ratio: Double
    let hasData: Bool
    let isPercentageMode: Bool

    private var showRing: Bool {
        hasData && isPercentageMode
    }

    private var clampedRatio: Double {
        min(max(ratio, 0), 1)
    }

    var body: some View {
        ZStack {
            if showRing {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 16, height: 16)

                Circle()
                    .trim(from: 0, to: clampedRatio)
                    .stroke(usageLevelColor(for: ratio), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 16)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 8))
            } else {
                Image(systemName: "leaf.fill")
            }
        }
    }
}
