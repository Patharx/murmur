import MurmurCore
import SwiftUI

enum Theme {
    static let bg = color(MurmurPalette.bg)
    static let surface = color(MurmurPalette.surface)
    static let text = color(MurmurPalette.text)
    static let accent = color(MurmurPalette.accent)
    static let accent400 = color(MurmurPalette.accent400)
    static let accent300 = color(MurmurPalette.accent300)
    static let accent700 = color(MurmurPalette.accent700)
    static let accent800 = color(MurmurPalette.accent800)
    static let neutral800 = color(MurmurPalette.neutral800)
    static let section = color(MurmurPalette.section)
    static let divider = color(MurmurPalette.text, opacity: MurmurPalette.dividerOpacity)
    static let textSecondary = color(MurmurPalette.text, opacity: MurmurPalette.textSecondary)
    static let textTertiary = color(MurmurPalette.text, opacity: MurmurPalette.textTertiary)
    static let textQuaternary = color(MurmurPalette.text, opacity: MurmurPalette.textQuaternary)
    static let outline = color(MurmurPalette.accent, opacity: 0.55)
    static let chipEdge = color(MurmurPalette.text, opacity: 0.14)

    static func color(_ rgb: MurmurRGB, opacity: Double = 1) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }
}

enum MurmurType {
    static func custom(_ size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
        Font.custom("Inter Variable", size: size, relativeTo: style).weight(weight)
    }

    static var screenTitle: Font { custom(29, weight: .medium, relativeTo: .largeTitle) }
    static var todayHeadline: Font { custom(28, weight: .medium, relativeTo: .title) }
    static var onboarding: Font { custom(31, weight: .medium, relativeTo: .largeTitle) }
    static var noteTitle: Font { custom(25, weight: .medium, relativeTo: .title2) }
    static var composeTitle: Font { custom(23, weight: .medium, relativeTo: .title2) }
    static var rowTitle: Font { custom(15, weight: .medium, relativeTo: .body) }
    static var body: Font { custom(15, weight: .regular, relativeTo: .body) }
    static var secondary: Font { custom(13, weight: .regular, relativeTo: .subheadline) }
    static var caption: Font { custom(12.5, weight: .regular, relativeTo: .caption) }
    static var meta: Font { custom(11, weight: .regular, relativeTo: .caption2) }
    static var sectionLabel: Font { custom(11, weight: .semibold, relativeTo: .caption2) }
    static var chip: Font { custom(10.5, weight: .semibold, relativeTo: .caption2) }
    static var timer: Font { custom(50, weight: .medium, relativeTo: .largeTitle) }
}

enum NoteClock {
    static func stamp(_ date: Date = Date()) -> NoteTimestamp {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        formatter.timeZone = .current
        return NoteTimestamp(date: date, text: formatter.string(from: date))
    }
}

struct OutlinedButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MurmurType.custom(15, weight: .medium, relativeTo: .body))
                .foregroundStyle(Theme.accent400)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.outline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct FolderChip: View {
    var title: String
    var active: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MurmurType.chip)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(active ? Theme.accent400 : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(active ? Theme.accent.opacity(0.16) : Color.clear, in: Capsule())
                .overlay(
                    Capsule().stroke(active ? Theme.accent : Theme.chipEdge, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    var icon: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PhosphorIcon(name: icon, size: 18)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 37, height: 37)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.chipEdge, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
