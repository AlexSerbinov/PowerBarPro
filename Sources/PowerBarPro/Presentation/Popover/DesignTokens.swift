import SwiftUI

// MARK: - Color Tokens

extension Color {
    enum PB {
        static let bg = Color(hex: 0x1C1B1F)
        static let surface = Color(hex: 0x2B2930)
        static let surfaceHover = Color(hex: 0x343240)

        static let textPrimary = Color(hex: 0xE8E5E0)
        static let textMuted = Color(hex: 0x8A8690)

        static let accent = Color(hex: 0xE8A44A)
        static let accentDim = Color(hex: 0xE8A44A).opacity(0.15)

        static let success = Color(hex: 0x5CB85C)
        static let error = Color(hex: 0xD64545)
        static let info = Color(hex: 0x5B9BD5)

        static let separator = Color(hex: 0xE8E5E0).opacity(0.08)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Typography

extension Font {
    enum PB {
        static let heroValue = Font.system(.largeTitle, design: .monospaced).weight(.semibold)
        static let heroUnit = Font.system(size: 20, design: .monospaced).weight(.regular)
        static let metricValue = Font.system(size: 18, design: .monospaced).weight(.semibold)
        static let metricSub = Font.system(size: 11, design: .monospaced)
        static let sectionTitle = Font.system(size: 11, weight: .semibold)
        static let body = Font.system(size: 13)
        static let caption = Font.system(size: 11)
        static let chartLabel = Font.system(size: 10, design: .monospaced)
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
}
