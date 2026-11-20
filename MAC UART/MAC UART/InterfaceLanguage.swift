import Foundation
import SwiftUI

enum InterfaceLanguage: String, CaseIterable {
    case system, chinese, english

    var code: String {
        switch self {
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
        case .chinese: return "zh-Hans"
        case .english: return "en"
        }
    }

    func text(_ key: String) -> String {
        guard code == "en" else { return key }
        return Self.englishBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    private static let englishBundle = Bundle.main.url(forResource: "en", withExtension: "lproj").flatMap(Bundle.init(url:))

    func source(_ value: String) -> String {
        for mode in [ConsoleMode.client, .server] where value.hasPrefix(mode.rawValue + " ") {
            return text(mode.rawValue) + value.dropFirst(mode.rawValue.count)
        }
        return value
    }
}

private struct InterfaceLanguageKey: EnvironmentKey {
    static let defaultValue = InterfaceLanguage.system
}

extension EnvironmentValues {
    var interfaceLanguage: InterfaceLanguage {
        get { self[InterfaceLanguageKey.self] }
        set { self[InterfaceLanguageKey.self] = newValue }
    }
}

// 保存提示模板和参数，切换语言时可以重绘已显示的连接状态。
struct InterfaceMessage: ExpressibleByStringLiteral {
    let key: String
    let arguments: [String]

    init(stringLiteral value: String) { self.init(value) }
    init(_ key: String, _ arguments: String...) {
        self.key = key
        self.arguments = arguments
    }

    func rendered(_ language: InterfaceLanguage) -> String {
        let template = language.text(key)
        guard !arguments.isEmpty else { return template }
        return String(format: template, arguments: arguments.map { language.text($0) })
    }
}
