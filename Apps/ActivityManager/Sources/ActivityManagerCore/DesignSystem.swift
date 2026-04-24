import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Design tokens used across every screen. Values are platform-adaptive
/// (macOS system colors for dark/light parity) and follow a 4pt spacing rhythm
/// per Apple HIG.
public enum DS {
    public enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 14
    }

    public enum Palette {
        #if canImport(AppKit)
        public static let windowBackground = Color(nsColor: .windowBackgroundColor)
        public static let card = Color(nsColor: .controlBackgroundColor)
        public static let surfaceRaised = Color(nsColor: .underPageBackgroundColor)
        public static let divider = Color(nsColor: .separatorColor)
        public static let textPrimary = Color(nsColor: .labelColor)
        public static let textSecondary = Color(nsColor: .secondaryLabelColor)
        public static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        #else
        public static let windowBackground = Color.gray.opacity(0.05)
        public static let card = Color.gray.opacity(0.1)
        public static let surfaceRaised = Color.gray.opacity(0.07)
        public static let divider = Color.gray.opacity(0.25)
        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary
        public static let textTertiary = Color.secondary.opacity(0.6)
        #endif
        public static let accent = Color.accentColor
        public static let danger = Color.red
        public static let success = Color.green
        public static let warning = Color.orange
    }
}

/// A raised card surface with consistent padding and corner radius. Use this
/// for any bounded content group (hero card, stats, empty state).
///
/// On macOS 26+ the card adopts the Liquid Glass material (`.glassEffect`) so
/// it picks up background blur, specular highlights, and motion. On older
/// systems it falls back to the flat raised fill.
public struct DSCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = DS.Space.lg, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .glassEffect(.regular, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.5))
    }
}

/// Primary action button style: Liquid Glass prominent on macOS 26+, falls
/// back to `.borderedProminent` on older systems.
public extension View {
    func dsPrimaryButtonStyle() -> some View {
        self.buttonStyle(.glassProminent)
    }

    func dsSecondaryButtonStyle() -> some View {
        self.buttonStyle(.glass)
    }

    /// Ambient backdrop for detail surfaces. Glass has nothing interesting to
    /// refract against a flat color, so we lay down a soft multi-hue gradient
    /// — the resulting highlights and parallax are what sells the material.
    func dsAmbientBackground() -> some View {
        self.background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.22),
                    Color.purple.opacity(0.14),
                    Color.pink.opacity(0.10),
                    Color.teal.opacity(0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

/// A small labelled section title with optional trailing accessory (e.g.
/// refresh button, count badge). Consistent across every detail pane.
public struct DSSectionHeader<Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let accessory: Accessory

    public init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            Spacer(minLength: DS.Space.md)
            accessory
        }
    }
}

/// A capsule pill with icon + label — for status badges, counters, etc.
public struct DSPill: View {
    public enum Kind {
        case neutral, success, warning, danger, info

        var background: Color {
            switch self {
            case .neutral: return DS.Palette.textSecondary.opacity(0.12)
            case .success: return DS.Palette.success.opacity(0.16)
            case .warning: return DS.Palette.warning.opacity(0.18)
            case .danger:  return DS.Palette.danger.opacity(0.18)
            case .info:    return DS.Palette.accent.opacity(0.16)
            }
        }
        var foreground: Color {
            switch self {
            case .neutral: return DS.Palette.textSecondary
            case .success: return DS.Palette.success
            case .warning: return DS.Palette.warning
            case .danger:  return DS.Palette.danger
            case .info:    return DS.Palette.accent
            }
        }
    }

    private let symbol: String?
    private let text: String
    private let kind: Kind

    public init(_ text: String, symbol: String? = nil, kind: Kind = .neutral) {
        self.text = text
        self.symbol = symbol
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: DS.Space.xs) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .foregroundStyle(kind.foreground)
        .glassEffect(.regular.tint(kind.foreground.opacity(0.22)), in: Capsule())
    }
}

/// Standard empty-state view with SF Symbol, title, and optional description.
public struct DSEmptyState: View {
    private let symbol: String
    private let title: String
    private let message: String?

    public init(symbol: String, title: String, message: String? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(DS.Palette.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(DS.Palette.textPrimary)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.xl)
    }
}

/// A compact key/value row used in stats grids and inspector panels.
public struct DSStat: View {
    private let label: String
    private let value: String
    private let symbol: String?

    public init(_ label: String, value: String, symbol: String? = nil) {
        self.label = label
        self.value = value
        self.symbol = symbol
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            Text(label)
                .font(.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer(minLength: DS.Space.sm)
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.Palette.textPrimary)
        }
    }
}
