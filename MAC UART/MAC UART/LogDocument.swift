import SwiftUI
import UniformTypeIdentifiers

struct LogDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    private let data: Data
    let filename: String

    init(entries: [Entry], format: WireFormat, language: InterfaceLanguage) {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        filename = language.text("收发日志") + "_" + clock.string(from: Date()) + "_" + language.text(format.rawValue) + ".txt"
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        var output = Data()
        for entry in entries {
            output.append(entry.logLine(format: format, language: language, clock: clock))
        }
        data = output
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
        filename = configuration.file.preferredFilename ?? "收发日志.txt"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension Entry {
    func logLine(format: WireFormat, language: InterfaceLanguage, clock: DateFormatter) -> Data {
        let direction = rx ? "RX" : "TX"
        let header = "[\(clock.string(from: time))] \(direction) [\(language.source(source))] "
        var output = Data(header.utf8)
        let payload = format == .hex ? hex : text
        output.append(contentsOf: payload.utf8)
        if payload.utf8.last != 10 { output.append(10) }
        return output
    }
}
