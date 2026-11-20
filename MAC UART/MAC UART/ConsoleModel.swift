import Foundation
import Combine
import Network

enum ConsoleMode: String, CaseIterable {
    case serial = "串口", client = "TCP 客户端", server = "TCP 服务端"
}

enum WireFormat: String, Codable, CaseIterable {
    case text = "文本", hex = "HEX"

    func encode(_ input: String, ending: String) throws -> Data {
        if self == .text { return Data((input + ending).utf8) }
        let digits = input.filter { !$0.isWhitespace }
        guard digits.utf8.count.isMultiple(of: 2),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw NSError(domain: "串口", code: 1, userInfo: [NSLocalizedDescriptionKey: "HEX 每字节需要两位十六进制数字，例如 01 A0 FF。"])
        }
        var data = Data()
        var index = digits.startIndex
        while index < digits.endIndex {
            let end = digits.index(index, offsetBy: 2)
            data.append(UInt8(digits[index..<end], radix: 16)!)
            index = end
        }
        return data
    }
}

struct Command: Identifiable, Codable {
    var id = UUID()
    var name = ""
    var input = ""
    var format = WireFormat.text
    var ending = ""
    // 可选字段兼容旧版本已保存的快捷指令。
    var includedInPoll: Bool?
    var delayMS: Int?
}

struct Entry: Identifiable {
    let id: Int
    let time: Date
    let source: String
    let rx: Bool
    let bytes: Data
    let text: String

    static let hexTable = (0...255).map { String(format: "%02X", $0) }
    var hex: String { bytes.map { Self.hexTable[Int($0)] }.joined(separator: " ") }
}

final class ConsoleModel: ObservableObject {
    @Published var ports: [String] = []
    @Published var path = ""
    @Published var settings = SerialSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "serial.parameters")
            }
        }
    }
    @Published var mode = ConsoleMode.serial {
        didSet { status = mode == .serial ? "串口未打开" : (mode == .server ? "尚未监听" : "尚未连接") }
    }
    @Published var host = "127.0.0.1"
    @Published var serverPort = "9000"
    @Published var clientPort = "9000"
    @Published var peers: [TCPPeer] = []
    @Published var target: UUID? {
        didSet { if oldValue != target { stopSchedule() } }
    }
    @Published private(set) var recording = false
    @Published private(set) var runningSchedule = false
    @Published private(set) var completedRounds = 0
    private var recorder: LogRecorder?
    private var steps: [(bytes: Data, delay: Int)] = []
    private var roundLimit = 0
    private var stepIndex = 0
    private var nextSend: DispatchWorkItem?
    private var sendingTo: UUID?
    private let tcp = TCPTransport()
    var ready: Bool { connected && !changing && !sending && (mode == .serial || target != nil) }
    @Published var connected = false
    @Published var changing = false
    @Published var sending = false
    @Published var status: InterfaceMessage = "串口未打开"
    @Published var error: String?
    @Published var entries: [Entry] = []
    @Published var rxBytes = 0
    @Published var txBytes = 0
    @Published var commands: [Command] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(commands) {
                UserDefaults.standard.set(data, forKey: "serial.commands")
            }
        }
    }
    private var serial = SerialPort()
    private var nextID = 0
    private var retained = 0
    private var tails: [String: Data] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: "serial.commands"),
           let saved = try? JSONDecoder().decode([Command].self, from: data) { commands = saved }
        if let data = UserDefaults.standard.data(forKey: "serial.parameters"),
           let saved = try? JSONDecoder().decode(SerialSettings.self, from: data) { settings = saved }
        tcp.event = { [weak self] in self?.handleTCP($0) }
        serial.event = { [weak self] e in DispatchQueue.main.async { self?.handle(e) } }
        refresh()
    }

    func refresh() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        let found = names.filter { $0.hasPrefix("cu.") }.map { "/dev/" + $0 }.sorted()
        if found != ports { ports = found }
        if !connected && !changing && !ports.contains(path) {
            path = ports.first(where: { !$0.contains("Bluetooth") && !$0.contains("debug-console") }) ?? ports.first ?? ""
        }
    }

    func startRecording(folder: URL, format: WireFormat, language: InterfaceLanguage) {
        guard recorder == nil else { return }
        do {
            let writer = try LogRecorder(folder: folder, format: format, language: language)
            writer.onFailure = { [weak self, weak writer] in
                guard let self, let writer, self.recorder === writer else { return }
                self.stopRecording()
            }
            recorder = writer
            recording = true
        } catch { self.error = error.localizedDescription }
    }

    func stopRecording() {
        guard let recorder else { return }
        self.recorder = nil
        recording = false
        do { try recorder.finish() }
        catch { self.error = error.localizedDescription }
    }

    func startSchedule(_ commands: [Command], interval: Int, rounds: Int) {
        guard ready, !runningSchedule, !commands.isEmpty else { return }
        guard (1...86_400_000).contains(interval), rounds >= 0 else {
            error = "请检查发送间隔和循环次数。"
            return
        }
        do {
            steps = try commands.map { command in
                let data = try command.format.encode(command.input, ending: command.ending)
                guard !data.isEmpty else { throw NSError(domain: "UART", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先输入发送内容。"]) }
                let delay = command.delayMS ?? interval
                guard (1...86_400_000).contains(delay) else {
                    throw NSError(domain: "UART", code: 2, userInfo: [NSLocalizedDescriptionKey: "请检查发送间隔和循环次数。"])
                }
                return (data, delay)
            }
        } catch { self.error = error.localizedDescription; return }
        stepIndex = 0
        completedRounds = 0
        roundLimit = rounds
        runningSchedule = true
        transmit(steps[0].bytes)
    }

    func stopSchedule() {
        nextSend?.cancel()
        nextSend = nil
        steps.removeAll()
        runningSchedule = false
    }

    private func didSend() {
        sending = false
        guard runningSchedule else { return }
        let delay = steps[stepIndex].delay
        stepIndex += 1
        if stepIndex == steps.count {
            stepIndex = 0
            completedRounds += 1
            if roundLimit > 0 && completedRounds >= roundLimit { stopSchedule(); return }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.runningSchedule else { return }
            guard self.ready else { self.stopSchedule(); return }
            self.transmit(self.steps[self.stepIndex].bytes)
        }
        nextSend = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: work)
    }

    func toggle() {
        stopSchedule()
        if mode == .serial {
            guard !changing else { return }
            changing = true
            if connected { serial.disconnect() }
            else { serial.connect(path, settings: settings) }
            return
        }
        if connected || changing { tcp.stop(); return }
        let portText = mode == .server ? serverPort : clientPort
        guard let number = UInt16(portText), number > 0, let port = NWEndpoint.Port(rawValue: number) else {
            error = "端口范围为 1–65535。"
            return
        }
        let address = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode != .client || !address.isEmpty else { error = "请输入服务器地址。"; return }
        changing = true
        if mode == .server {
            status = "正在启动监听…"
            tcp.listen(port: port)
        } else {
            status = "正在连接…"
            tcp.connect(host: address, port: port)
        }
    }

    private func handleTCP(_ event: TCPEvent) {
        switch event {
        case .listening:
            connected = true
            changing = false
            status = InterfaceMessage("正在监听 TCP 端口 %@", serverPort)
        case .joined(let peer):
            peers.append(peer)
            if target == nil { target = peer.id }
            connected = true
            changing = false
            status = mode == .client ? InterfaceMessage("已连接 %@", peer.address) : InterfaceMessage("正在监听 %@ · 客户端 %@", serverPort, String(peers.count))
        case .left(let id, let reason):
            peers.removeAll { $0.id == id }
            tails.removeValue(forKey: id.uuidString)
            if target == id { target = peers.first?.id }
            if sendingTo == id { sending = false; sendingTo = nil }
            status = InterfaceMessage("正在监听 %@ · %@", serverPort, reason)
        case .stopped(let reason):
            stopSchedule()
            peers.removeAll()
            target = nil
            sendingTo = nil
            changing = false
            connected = false
            sending = false
            tails.removeAll()
            status = InterfaceMessage(reason)
        case .received(let peer, let data):
            append(data, time: Date(), rx: true, peer: peer)
        case .sent(let peer, let data):
            append(data, time: Date(), rx: false, peer: peer)
            didSend()
            sendingTo = nil
        case .sendFailed(let reason):
            stopSchedule()
            sending = false
            sendingTo = nil
            error = reason
        }
    }

    func send(_ command: Command) {
        guard ready, !runningSchedule else { return }
        do {
            let data = try command.format.encode(command.input, ending: command.ending)
            guard !data.isEmpty else { error = "请先输入发送内容。"; return }
            transmit(data)
        } catch { self.error = error.localizedDescription }
    }

    private func transmit(_ data: Data) {
        sending = true
        if mode == .serial { serial.send(data) }
        else if let target { sendingTo = target; tcp.send(data, to: target) }
    }

    func clear() {
        entries.removeAll()
        retained = 0
        rxBytes = 0
        txBytes = 0
        if !recording { tails.removeAll() }
    }

    // 保留分批到达的 UTF-8 字符前缀，待下次接收时合并解码。
    private func decoded(_ bytes: Data, rx: Bool, stream: String) -> String {
        guard rx else { return String(decoding: bytes, as: UTF8.self) }
        var combined = (tails.removeValue(forKey: stream) ?? Data()) + bytes
        for n in 1...min(3, combined.count) {
            let suffix = combined.suffix(n)
            let first = suffix.first!
            let length = (194...223).contains(first) ? 2 : (224...239).contains(first) ? 3 : (240...244).contains(first) ? 4 : 0
            if length > n && suffix.dropFirst().allSatisfy({ $0 & 0xc0 == 0x80 }) {
                tails[stream] = Data(suffix)
                combined.removeLast(n)
                break
            }
        }
        return String(decoding: combined, as: UTF8.self)
    }

    private func append(_ bytes: Data, time: Date, rx: Bool, peer: TCPPeer? = nil) {
        nextID += 1
        retained += bytes.count
        while entries.count >= 3000 || (retained > 1_048_576 && !entries.isEmpty) {
            retained -= entries.removeFirst().bytes.count
        }
        let entry = Entry(id: nextID, time: time, source: peer.map { mode.rawValue + " " + $0.address } ?? path, rx: rx, bytes: bytes, text: decoded(bytes, rx: rx, stream: peer?.id.uuidString ?? path))
        recorder?.append(entry)
        entries.append(entry)
        if rx { rxBytes += bytes.count } else { txBytes += bytes.count }
    }

    private func handle(_ event: PortEvent) {
        switch event {
        case .connected:
            changing = false
            connected = true
            status = "已连接"
        case .closed(let reason):
            stopSchedule()
            connected = false
            changing = false
            sending = false
            status = reason
            tails.removeAll()
            refresh()
        case .received(let bytes, let time): append(bytes, time: time, rx: true)
        case .sent(let bytes, let time): append(bytes, time: time, rx: false)
        case .sendFinished: didSend()
        }
    }
}
