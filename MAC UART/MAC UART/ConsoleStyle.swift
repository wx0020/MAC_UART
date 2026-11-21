import SwiftUI

enum ConsoleStyle {
    static let blue = adaptive(0x2365CC, 0x79B2FF)
    static let ink = adaptive(0x142B46, 0xE2EEFF)
    static let muted = adaptive(0x52687F, 0xA2B8CE)
    static let border = adaptive(0xC8D7E5, 0x314659)
    static let panel = adaptive(0xFAFCFF, 0x192837)
    static let field = adaptive(0xF0F5FA, 0x111F2D)
    static let base = adaptive(0xE6EEF6, 0x101A26)
    static let sky = adaptive(0xD1E7FC, 0x1B344D)
    static let receiveAccent = adaptive(0x11736D, 0x38D6C7)
    static let sendAccent = adaptive(0x93531C, 0xFFB563)
    static let rx = Color(red: 0.22, green: 0.84, blue: 0.78)
    static let tx = Color(red: 1, green: 0.71, blue: 0.39)
    static let terminal = NSColor(srgbRed: 0.052, green: 0.086, blue: 0.132, alpha: 1)

    private static func adaptive(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func consolePanel(_ color: Color = ConsoleStyle.panel) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(ConsoleStyle.border, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct ConsoleActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11).frame(height: 29)
            .foregroundStyle(prominent ? Color.white : ConsoleStyle.ink)
            .background(prominent ? Color(red: 0.13, green: 0.35, blue: 0.66) : ConsoleStyle.field,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(ConsoleStyle.border.opacity(prominent ? 0 : 0.9)) }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}
