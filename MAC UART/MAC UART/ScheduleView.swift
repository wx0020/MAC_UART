import SwiftUI

private typealias FormState<T> = State<T>

struct ScheduleView: View {
    @Environment(\.interfaceLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ConsoleModel
    let draft: Command
    @AppStorage("schedule.poll") private var poll = false
    @AppStorage("schedule.interval") private var interval = "1000"
    @AppStorage("schedule.rounds") private var rounds = "1"
    @FormState private var message = ""

    private func move(_ id: UUID, by offset: Int) {
        guard let i = model.commands.firstIndex(where: { $0.id == id }),
              model.commands.indices.contains(i + offset) else { return }
        model.commands.swapAt(i, i + offset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text("自动发送")).font(.title2.bold())
            Picker(language.text("模式"), selection: $poll) {
                Text(language.text("定时发送")).tag(false)
                Text(language.text("多指令轮询")).tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            if poll {
                Text(language.text("从上到下发送勾选项，可为每条指令指定间隔。")).font(.caption)
                ScrollView {
                    VStack(alignment: .leading) {
                        if model.commands.isEmpty { Text(language.text("还没有快捷指令")).foregroundStyle(.secondary) }
                        ForEach($model.commands) { $cmd in
                            HStack {
                                Toggle(cmd.name, isOn: Binding(get: { cmd.includedInPoll ?? false }, set: { cmd.includedInPoll = $0 }))
                                    .toggleStyle(.checkbox).lineLimit(1)
                                Spacer()
                                TextField(language.text("默认"), text: Binding(get: { cmd.delayMS.map(String.init) ?? "" }, set: {
                                    if $0.isEmpty { cmd.delayMS = nil }
                                    else if let n = Int($0), n >= 0 { cmd.delayMS = n }
                                })).frame(width: 70)
                                Text("ms")
                                Button { move(cmd.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .disabled(cmd.id == model.commands.first?.id).help(language.text("上移"))
                                Button { move(cmd.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .disabled(cmd.id == model.commands.last?.id).help(language.text("下移"))
                            }
                        }
                    }.padding(5)
                }.frame(height: 175)
            } else {
                Text(draft.input.isEmpty ? language.text("请先在发送区输入数据。") : draft.input)
                    .lineLimit(3).font(.system(.body, design: .monospaced))
            }
            HStack {
                Text(language.text("默认间隔"))
                TextField("1000", text: $interval).frame(width: 80)
                Text("ms")
                Spacer()
                Text(language.text("循环次数"))
                TextField("1", text: $rounds).frame(width: 70)
            }
            Text(language.text("0 次表示持续循环；间隔从上一条发送完成后计算。")).font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(language.text(message)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(language.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(language.text("开始发送")) {
                    guard let delay = Int(interval), let count = Int(rounds) else {
                        message = "请检查发送间隔和循环次数。"; return
                    }
                    let commands = poll ? model.commands.filter { $0.includedInPoll == true } : [draft]
                    model.startSchedule(commands, interval: delay, rounds: count)
                    if model.runningSchedule { dismiss() }
                    else if let error = model.error { message = error; model.error = nil }
                }.keyboardShortcut(.defaultAction)
                    .disabled(!model.ready || (poll ? !model.commands.contains { $0.includedInPoll == true } : draft.input.isEmpty))
            }
        }.padding(22).frame(width: 470)
    }
}
