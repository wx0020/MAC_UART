import UniformTypeIdentifiers
import SwiftUI
import Combine

private typealias ViewState<Value> = State<Value>

private let teal = Color(red: 0.08, green: 0.57, blue: 0.53)
private let canvas = Color(red: 0.075, green: 0.105, blue: 0.14)
private let stamp: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

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
    @ObservedObject var model: ConsoleModel
    @ViewState private var draft = Command()
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
        VStack(spacing: 0) {
            connectionBar
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label(language.text("收发日志"), systemImage: "terminal").font(.headline)
                        Spacer()
                        FormatPicker(value: $display)
                        Toggle(language.text("跟随"), isOn: $follow).toggleStyle(.checkbox)
                        Button(language.text("导出日志…")) {
                            exportDocument = LogDocument(entries: model.entries, format: display, language: language)
                            exporting = true
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                        .disabled(model.entries.isEmpty)
                        Button(language.text("清空")) { model.clear() }.disabled(model.entries.isEmpty)
                    }.padding()
                    logView
                    HStack {
                        Text(language.text("发送数据")).font(.headline)
                        Spacer()
                        FormatPicker(value: $draft.format)
                        EndingPicker(value: $draft.ending).disabled(draft.format == .hex)
                    }.padding([.horizontal, .top])
                    TextEditor(text: $draft.input).font(.system(.body, design: .monospaced))
                        .padding(5).frame(height: 76)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                        .padding(.horizontal).padding(.top, 10)
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
                            .disabled(draft.input.isEmpty)
                        Button { model.send(draft) } label: { Label(language.text("发送"), systemImage: "paperplane.fill") }
                            .buttonStyle(.borderedProminent).tint(teal).keyboardShortcut(.return, modifiers: .command)
                            .disabled(!ready || draft.input.isEmpty)
                    }.padding()
                }.frame(minWidth: 510)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label(language.text("快捷指令"), systemImage: "bolt.fill").font(.headline)
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
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(cmd.name).fontWeight(.medium).lineLimit(1)
                                            Text(language.text(cmd.format.rawValue) + "  ·  " + cmd.input).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(!ready).help(language.text("发送此指令"))
                                    Menu {
                                        Button(language.text("编辑")) { editor = cmd }
                                        Button(language.text("删除"), role: .destructive) { model.commands.removeAll { $0.id == cmd.id } }
                                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                                }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 7))
                            }
                        }.padding(10)
                    }
                }.frame(minWidth: 215, idealWidth: 248, maxWidth: 410).background(Color(nsColor: .controlBackgroundColor))
            }
            Divider()
            HStack {
                Circle().fill(model.connected ? teal : .secondary).frame(width: 8, height: 8)
                Text(model.status.rendered(language)).lineLimit(1)
                Button {
                    if model.recording { model.stopRecording() } else { chooseFolder = true }
                } label: {
                    Label(language.text(model.recording ? "停止录制" : "连续录制…"),
                          systemImage: model.recording ? "stop.circle.fill" : "record.circle")
                }.foregroundStyle(model.recording ? Color.red : Color.primary)
                    .help(language.text("选择目录，以当前显示格式录制，每卷约 10 MiB。"))
                Spacer()
                Text(model.mode == .serial ? model.settings.summary : language.text(model.mode.rawValue)).foregroundStyle(.secondary)
                Divider().frame(height: 12)
                Text("RX  \(model.rxBytes) B     TX  \(model.txBytes) B").monospacedDigit()
            }.font(.caption).padding(.horizontal).padding(.vertical, 7)
        }.frame(minWidth: 830, minHeight: 520)
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
            }
            Spacer()
            Button(actionTitle) { model.toggle() }.buttonStyle(.borderedProminent).tint(teal)
                .disabled(model.mode == .serial && (model.path.isEmpty || model.changing))
        }.padding()
    }

    private var actionTitle: String {
        if model.mode == .serial { return model.connected ? language.text("关闭串口") : language.text("打开串口") }
        if model.changing { return language.text("取消") }
        if model.mode == .server { return model.connected ? language.text("停止监听") : language.text("开始监听") }
        return model.connected ? language.text("断开连接") : language.text("连接")
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(stamp.string(from: entry.time)).foregroundStyle(.white.opacity(0.58))
                            Text(entry.rx ? "RX" : "TX").foregroundStyle(entry.rx ? .mint : .orange)
                            if entry.source.hasPrefix("TCP ") { Text(language.source(entry.source)).foregroundStyle(.white.opacity(0.65)).lineLimit(2) }
                            Text(verbatim: display == .hex ? entry.hex : entry.text).foregroundStyle(.white)
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.id(entry.id)
                    }
                }.font(.system(size: 12, design: .monospaced)).padding(14)
            }.background(canvas).overlay {
                if model.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg").font(.largeTitle).foregroundStyle(.mint)
                        Text(model.connected ? language.text("等待收发数据") : language.text("建立连接后查看收发记录")).foregroundStyle(.white.opacity(0.72))
                    }
                }
            }.onChange(of: model.entries.last?.id) { _, id in if follow, let id { proxy.scrollTo(id, anchor: .bottom) } }
            .onChange(of: follow) { _, enabled in if enabled, let id = model.entries.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
        }
    }
}

private struct CommandEditor: View {
    @Environment(\.interfaceLanguage) private var language
    @ViewState var command: Command
    var save: (Command) -> Void
    @Environment(\.dismiss) var dismiss
    @ViewState private var message = ""

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
            if !message.isEmpty { Text(language.text(message)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(language.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(language.text("保存")) {
                    do {
                        guard !(try command.format.encode(command.input, ending: command.ending)).isEmpty else {
                            message = language.text("请输入发送内容。"); return
                        }
                        save(command)
                        dismiss()
                    } catch { message = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(command.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || command.input.isEmpty)
            }
        }.padding(22).frame(width: 400)
    }
}
