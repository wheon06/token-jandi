import SwiftUI

/// Visual language of the popover: one accent, no strokes or shadows, a clear
/// type hierarchy, and grouping by spacing and light containers.
enum Theme {
    /// The single accent. Used for the heatmap, bars and the selected state only.
    static let accent = Color.green

    static let padding: CGFloat = 16
    static let groupSpacing: CGFloat = 18
    static let rowSpacing: CGFloat = 10
    static let cornerRadius: CGFloat = 12

    static let hero = Font.system(size: 38, weight: .bold, design: .rounded)
    /// Supporting numbers under the hero.
    static let stat = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let number = Font.system(size: 12, weight: .semibold, design: .rounded)

    /// Light container for a group of related rows.
    static var groupBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    /// Track behind progress bars.
    static var track: Color {
        Color(nsColor: .separatorColor).opacity(0.3)
    }
}

/// A titled group: small gray title, then rows inside one light container.
struct SectionGroup<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(Theme.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
            }
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.groupBackground)
            .cornerRadius(Theme.cornerRadius)
        }
    }
}

/// Label on the left, control on the right.
struct SettingRow<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.body)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// Thin progress bar with the accent, turning red only when nearly exhausted.
struct UsageBar: View {
    let fraction: Double

    private var tint: Color {
        fraction >= 0.9 ? .red : Theme.accent
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, proxy.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 5)
    }
}
