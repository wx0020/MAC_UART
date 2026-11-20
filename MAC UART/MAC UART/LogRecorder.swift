import Foundation

// 每次录制独占一个文件名前缀和写入队列。停止时排空队列后再释放目录访问权限。
final class LogRecorder {
    private let queue = DispatchQueue(label: "uart.recording", qos: .utility)
    private let folder: URL
    private let scoped: Bool
    private let prefix: String
    private let limit: Int
    private let format: WireFormat
    private let language: InterfaceLanguage
    private let clock = DateFormatter()
    private var handle: FileHandle?
    private var part = 0
    private var length = 0
    private var finished = false
    private var writeError: Error?
    var onFailure: (() -> Void)?

    init(folder: URL, format: WireFormat, language: InterfaceLanguage, limit: Int = 10 * 1024 * 1024) throws {
        self.folder = folder
        self.format = format
        self.language = language
        self.limit = limit
        scoped = folder.startAccessingSecurityScopedResource()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "yyyyMMdd-HHmmss"
        prefix = "UART-" + clock.string(from: Date()) + "-" + String(UUID().uuidString.prefix(8))
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        do { try nextFile() }
        catch {
            if scoped { folder.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private func nextFile() throws {
        try handle?.close()
        handle = nil
        part += 1
        let url = folder.appendingPathComponent(prefix + String(format: "-%04d.txt", part))
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        length = 0
    }

    func append(_ entry: Entry) {
        queue.async { [self] in
            guard !finished, writeError == nil else { return }
            do {
                let data = entry.logLine(format: format, language: language, clock: clock)
                if length > 0 && length + data.count > limit { try nextFile() }
                try handle?.write(contentsOf: data)
                length += data.count
            } catch {
                writeError = error
                DispatchQueue.main.async { self.onFailure?() }
            }
        }
    }

    func finish() throws {
        try queue.sync {
            guard !finished else { return }
            finished = true
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            try handle?.close()
            handle = nil
            if let writeError { throw writeError }
        }
    }
}
