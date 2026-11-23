import UniformTypeIdentifiers
import SwiftUI
import Combine

private typealias ViewState<Value> = State<Value>

private struct TrafficCounter: View {
    let label: String
    let bytes: Int
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(ConsoleStyle.muted)
                Text(String(bytes) + " B").font(.system(size: 16, weight: .medium, design: .monospaced)).foregroundStyle(ConsoleStyle.ink)
            }
        }.accessibilityElement(children: .combine)
    }
}
private struct FormatPicker: View {
    @Environment(\.interfaceLanguage) private var language
    @Binding var value: WireFormat
    var body: some View {
        Picker(language.text("数据格式"), selection: $value) {
            ForEach(WireFormat.allCases, id: \.self) { Text(language.text($0.rawValue)).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 110)
    }
}

private struct EndingPicker: View {
    @Environment(\.interfaceLanguage) private var language
    @Binding var value: String
    var body: some View {
        Picker(language.text("行尾"), selection: $value) {
            Text(language.text("无")).tag("")
            Text("CR").tag("\r")
            Text("LF").tag("\n")
            Text("CR LF").tag("\r\n")
        }.fixedSize()
    }
}

struct ContentView: View {
    @Environment(\.interfaceLanguage) private var language
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: ConsoleModel
    @ViewState private var draft = Command()
    @ViewState private var draftByteCount: Int? = 0
    @FocusState private var editingDraft: Bool
    @ViewState private var display = WireFormat.text
    @ViewState private var editor: Command?
    @ViewState private var exportDocument: LogDocument?
    @ViewState private var exporting = false
    @ViewState private var chooseFolder = false
    @ViewState private var showSchedule = false
    @ViewState private var follow = true
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private var ready: Bool { model.ready && !model.runningSchedule }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityBar
            connectionBar
            HSplitView {
                VStack(spacing: 12) {
                    trafficPanel
                    sendPanel
                }.frame(minWidth: 505).padding(.trailing, 6)
                commandPanel.padding(.leading, 6)
            }
        }.padding(16).frame(minWidth: 830, minHeight: 535)
        .background(LinearGradient(colors: [ConsoleStyle.sky, ConsoleStyle.base, ConsoleStyle.field],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .tint(ConsoleStyle.blue)
        .onChange(of: draft, initial: true) { _, command in
            draftByteCount = command.byteCount
        }
        .onReceive(refresh) { _ in model.refresh() }
        .onDisappear { model.stopSchedule(); model.stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.stopSchedule()
            model.stopRecording()
        }
        .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let folder): model.startRecording(folder: folder, format: display, language: language)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { model.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showSchedule) { ScheduleView(model: model, draft: draft) }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .plainText,
                      defaultFilename: exportDocument?.filename) { result in
            exportDocument = nil
            if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                model.error = language.text("导出日志失败：") + error.localizedDescription
            }
        }
        .sheet(item: $editor) { command in
            CommandEditor(command: command) { updated in
                if let i = model.commands.firstIndex(where: { $0.id == updated.id }) { model.commands[i] = updated }
                else { model.commands.append(updated) }
            }
        }
        .alert(language.text("通信提示"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(language.text("确定")) { model.error = nil }
        } message: { Text(language.text(model.error ?? "")) }
    }

    private var identityBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white).frame(width: 41, height: 41)
                .background(LinearGradient(colors: [Color(red: 0.17, green: 0.43, blue: 0.72), Color(red: 0.06, green: 0.17, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 11))
            Text("MAC UART").font(.system(size: 26, weight: .semibold, design: .rounded))
                .tracking(-0.8).foregroundStyle(ConsoleStyle.ink)
            Divider().frame(height: 23)
            HStack(spacing: 6) {
                Circle().fill(model.connected ? Color.green : ConsoleStyle.muted).frame(width: 7, height: 7)
                Text(model.status.rendered(language)).lineLimit(1).help(model.status.rendered(language))
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(ConsoleStyle.ink)
            Spacer(minLength: 8)
            TrafficCounter(label: "RX", bytes: model.rxBytes, symbol: "arrow.down.left", tint: ConsoleStyle.receiveAccent)
            Divider().frame(height: 24)
            TrafficCounter(label: "TX", bytes: model.txBytes, symbol: "arrow.up.right", tint: ConsoleStyle.sendAccent)
        }
    }

    private var trafficPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "terminal").foregroundStyle(ConsoleStyle.rx)
                Text(language.text("收发日志")).font(.headline)
                Spacer(minLength: 2)
                FormatPicker(value: $display)
                Toggle(language.text("跟随"), isOn: $follow).toggleStyle(.checkbox).controlSize(.small)
                Divider().frame(height: 17)
                Button {
                    if model.recording { model.stopRecording() } else { chooseFolder = true }
                } label: {
                    Label(language.text(model.recording ? "停止" : "录制"), systemImage: model.recording ? "stop.circle.fill" : "record.circle")
                        .foregroundStyle(model.recording ? Color.red : .white)
                }.accessibilityLabel(language.text(model.recording ? "停止录制" : "连续录制…"))
                    .help(language.text(model.recording ? "停止录制" : "连续录制…"))
                Button {
                    exportDocument = LogDocument(entries: model.entries, format: display, language: language)
                    exporting = true
                } label: { Label(language.text("导出"), systemImage: "square.and.arrow.up") }
                    .accessibilityLabel(language.text("导出日志…")).help(language.text("导出日志…"))
                    .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.entries.isEmpty)
                Button { model.clear() } label: { Image(systemName: "trash") }
                    .accessibilityLabel(language.text("清空")).help(language.text("清空")).disabled(model.entries.isEmpty)
            }.labelStyle(.titleAndIcon).buttonStyle(.borderless).padding(.horizontal, 16).frame(height: 48)
                .foregroundStyle(.white).environment(\.colorScheme, .dark)
                .background(Color(red: 0.095, green: 0.15, blue: 0.22))
            logView
            HStack(spacing: 8) {
                Image(systemName: model.mode == .serial ? "cable.connector" : "network")
                Text(model.mode == .serial ? model.settings.summary : language.text(model.mode.rawValue))
                Spacer()
                if model.recording {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text(language.text("录制中"))
                }
                Text(String(model.entries.count) + " " + language.text("条记录"))
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.white.opacity(0.73))
                .padding(.horizontal, 16).frame(height: 27)
                .background(Color(red: 0.08, green: 0.12, blue: 0.18))
        }.consolePanel(Color(nsColor: ConsoleStyle.terminal))
    }

    private var sendPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(language.text("发送数据"), systemImage: "paperplane").font(.headline).foregroundStyle(ConsoleStyle.ink)
                Spacer()
                if let draftByteCount {
                    Text("\(draftByteCount) B").monospacedDigit()
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("draftByteCount")
                }
                FormatPicker(value: $draft.format)
                EndingPicker(value: $draft.ending).disabled(draft.format == .hex)
            }.padding([.horizontal, .top])
            TextEditor(text: $draft.input)
                .focused($editingDraft)
                .accessibilityLabel(language.text("发送内容"))
                .accessibilityIdentifier("sendDraft")
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden).padding(6).frame(height: 58)
                .background(ConsoleStyle.field, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                .padding(.horizontal).padding(.top, 10)
            if draftByteCount == nil {
                Label(language.text("HEX 每字节需要两位十六进制数字，例如 01 A0 FF。"), systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.red).padding(.horizontal).padding(.top, 4)
            }
            HStack {
                if model.runningSchedule {
                    Button(language.text("停止自动发送")) { model.stopSchedule() }
                } else {
                    Button(language.text("自动发送…")) { showSchedule = true }
                }
                if model.runningSchedule || model.completedRounds > 0 {
                    Text(language.text("已完成轮数") + " " + String(model.completedRounds))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer()
                Button(language.text("存为指令")) { editor = Command(input: draft.input, format: draft.format, ending: draft.ending) }
                    .disabled((draftByteCount ?? 0) == 0)
                Button { model.send(draft) } label: { Label(language.text("发送"), systemImage: "paperplane.fill") }
                    .buttonStyle(ConsoleActionStyle(prominent: true)).keyboardShortcut(.return, modifiers: .command)
                    .disabled(!ready || (draftByteCount ?? 0) == 0)
            }.buttonStyle(ConsoleActionStyle()).padding(.horizontal).padding(.vertical, 10)
        }.consolePanel()
    }

    private var commandPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(language.text("快捷指令"), systemImage: "square.stack.3d.up").font(.headline).foregroundStyle(ConsoleStyle.ink)
                Spacer()
                Button { editor = Command() } label: { Image(systemName: "plus") }.help(language.text("添加指令"))
            }.padding()
            Divider()
            if model.commands.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "rectangle.stack.badge.plus").font(.title)
                    Text(language.text("还没有快捷指令")).font(.headline)
                    Text(language.text("点 + 新建，或从发送区保存。")).font(.caption)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 54)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.commands) { cmd in
                        HStack {
                            Button { model.send(cmd) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: cmd.format == .hex ? "number" : "chevron.left.forwardslash.chevron.right")
                                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ConsoleStyle.blue)
                                        .frame(width: 29, height: 31).background(ConsoleStyle.sky, in: RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(cmd.name).foregroundStyle(ConsoleStyle.ink).fontWeight(.semibold).lineLimit(1)
                                        Text(language.text(cmd.format.rawValue) + "  ·  " + cmd.input).font(.system(.caption, design: .monospaced)).foregroundStyle(ConsoleStyle.muted).lineLimit(2)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!ready).help(language.text("发送此指令"))
                            Menu {
                                Button(language.text("载入发送区")) {
                                    draft = Command(input: cmd.input, format: cmd.format, ending: cmd.ending)
                                    editingDraft = true
                                }
                                Button(language.text("编辑")) { editor = cmd }
                                Button(language.text("删除"), role: .destructive) { model.commands.removeAll { $0.id == cmd.id } }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                                .accessibilityLabel(language.text("指令操作") + " · " + cmd.name)
                        }.padding(10).background(ConsoleStyle.field, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(10)
            }
        }.frame(minWidth: 212, idealWidth: 245, maxWidth: 380, maxHeight: .infinity, alignment: .top).consolePanel()
    }

    private var connectionBar: some View {
        HStack(spacing: 12) {
            Picker(language.text("模式"), selection: $model.mode) {
                ForEach(ConsoleMode.allCases, id: \.self) { Text(language.text($0.rawValue)).tag($0) }
            }.fixedSize().disabled(model.connected || model.changing)
            Divider().frame(height: 18)
            if model.mode == .serial {
                Picker(language.text("串口"), selection: $model.path) {
                    if model.ports.isEmpty { Text(language.text("未发现串口")).tag("") }
                    ForEach(model.ports, id: \.self) { Text($0).tag($0) }
                    if !model.path.isEmpty && !model.ports.contains(model.path) { Text(model.path).tag(model.path) }
                }.disabled(model.connected || model.changing)
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help(language.text("刷新设备列表"))
                Picker(language.text("波特率"), selection: $model.settings.baud) {
                    ForEach(SerialSettings.rates, id: \.self) { Text(String($0)).tag($0) }
                }.fixedSize().disabled(model.connected || model.changing)
                Button { openWindow(id: "parameters") } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel(language.text("串口参数设置")).help(language.text("串口参数设置…"))
            } else {
                if model.mode == .client {
                    TextField(language.text("服务器 IP 或主机名"), text: $model.host).frame(maxWidth: 235)
                        .disabled(model.connected || model.changing)
                }
                Text(model.mode == .server ? language.text("监听端口") : language.text("端口"))
                TextField("1–65535", text: model.mode == .server ? $model.serverPort : $model.clientPort)
                    .frame(width: 75).disabled(model.connected || model.changing)
                if model.mode == .server && !model.peers.isEmpty {
                    Picker(language.text("发送至"), selection: $model.target) {
                        ForEach(model.peers) { Text($0.address).tag(Optional($0.id)) }
                    }.frame(maxWidth: 340).disabled(model.sending || model.runningSchedule)
                }
                Spacer()
            }
            Button(actionTitle) { model.toggle() }.buttonStyle(ConsoleActionStyle(prominent: true))
                .disabled(model.mode == .serial && (model.path.isEmpty || model.changing))
            if model.mode == .serial { Spacer() }
        }.padding(.horizontal, 14).frame(height: 49).consolePanel()
    }

    private var actionTitle: String {
        if model.mode == .serial { return model.connected ? language.text("关闭串口") : language.text("打开串口") }
        if model.changing { return language.text("取消") }
        if model.mode == .server { return model.connected ? language.text("停止监听") : language.text("开始监听") }
        return model.connected ? language.text("断开连接") : language.text("连接")
    }

    private var logView: some View {
        ConsoleLogView(entries: model.entries, format: display, language: language, follow: follow)
            .overlay {
                if model.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg").font(.largeTitle).foregroundStyle(.mint)
                        Text(model.connected ? language.text("等待收发数据") : language.text("建立连接后查看收发记录")).foregroundStyle(.white.opacity(0.72))
                    }.allowsHitTesting(false)
                }
            }
    }
}

private struct CommandEditor: View {
    @Environment(\.interfaceLanguage) private var language
    @ViewState var command: Command
    var save: (Command) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("快捷指令")).font(.title2.bold())
            TextField(language.text("指令名称"), text: $command.name)
            HStack {
                FormatPicker(value: $command.format)
                EndingPicker(value: $command.ending).disabled(command.format == .hex)
            }
            Text(language.text("发送内容")).font(.headline)
            TextEditor(text: $command.input).font(.system(.body, design: .monospaced)).frame(height: 95)
            if command.byteCount == nil {
                Text(language.text("HEX 每字节需要两位十六进制数字，例如 01 A0 FF。")).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(language.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(language.text("保存")) {
                    save(command)
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(command.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (command.byteCount ?? 0) == 0)
            }
        }.padding(22).frame(width: 400).background(ConsoleStyle.panel).tint(ConsoleStyle.blue)
    }
}
