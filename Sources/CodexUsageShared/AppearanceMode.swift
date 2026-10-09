import SwiftUI

public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    public init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .system
    }
}

public struct UsageMonitorIcon: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color(red: 0.06, green: 0.10, blue: 0.16))

            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    Color(red: 0.22, green: 0.83, blue: 0.53),
                    style: StrokeStyle(lineWidth: max(1.2, size * 0.09), lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(size * 0.14)

            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
