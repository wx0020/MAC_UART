import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(\.interfaceLanguage) private var language
    @ObservedObject var model: ConsoleModel
    private var locked: Bool { model.mode == .serial && (model.connected || model.changing) }

    var body: some View {
        Form {
            Picker(language.text("波特率"), selection: $model.settings.baud) {
                ForEach(SerialSettings.rates, id: \.self) { Text(String($0)).tag($0) }
            }
            Picker(language.text("数据位"), selection: $model.settings.bits) {
                ForEach(5...8, id: \.self) { Text(String($0)).tag($0) }
            }
            Picker(language.text("校验位"), selection: $model.settings.parity) {
                ForEach(Parity.allCases, id: \.self) { Text(language.text($0.rawValue)).tag($0) }
            }
            Picker(language.text("停止位"), selection: $model.settings.stops) {
                ForEach(1...2, id: \.self) { Text(String($0)).tag($0) }
            }
            Picker(language.text("流控"), selection: $model.settings.flow) {
                ForEach(FlowControl.allCases, id: \.self) { Text(language.text($0.rawValue)).tag($0) }
            }
            Text(locked ? language.text("请先关闭串口，再修改参数。") : language.text("设置自动保存，下次打开串口时生效。"))
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(locked).padding(24).frame(width: 340).background(ConsoleStyle.panel).tint(ConsoleStyle.blue)
    }
}

struct SerialSettingsMenu: Commands {
    @Binding var language: InterfaceLanguage
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu(language.text("串口")) {
            Button(language.text("串口参数设置…")) { openWindow(id: "parameters") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu(language.text("界面语言")) {
            Picker(language.text("界面语言"), selection: $language) {
                Text(language.text("跟随系统")).tag(InterfaceLanguage.system)
                Text("简体中文").tag(InterfaceLanguage.chinese)
                Text("English").tag(InterfaceLanguage.english)
            }.pickerStyle(.inline)
        }
    }
}
