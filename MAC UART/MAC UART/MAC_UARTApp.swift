import SwiftUI

@main
struct MAC_UARTApp: App {
    @StateObject private var model = ConsoleModel()

    @AppStorage("interface.language") private var language = InterfaceLanguage.system

    var body: some Scene {
        Window(language.text("串口工作台"), id: "serial") {
            ContentView(model: model)
                .environment(\.interfaceLanguage, language)
                .environment(\.locale, Locale(identifier: language.code))
        }
        .defaultSize(width: 1110, height: 710)
        .commands { SerialSettingsMenu(language: $language) }
        Window(language.text("串口参数设置"), id: "parameters") {
            ConnectionSettingsView(model: model)
                .environment(\.interfaceLanguage, language)
                .environment(\.locale, Locale(identifier: language.code))
        }.windowResizability(.contentSize)
    }
}
