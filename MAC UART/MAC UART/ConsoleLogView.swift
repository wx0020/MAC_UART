import SwiftUI
import AppKit

final class ConsoleTextView: NSTextView {
    override func copy(_ sender: Any?) {
        copySelection(to: .general)
    }

    @discardableResult
    func copySelection(to pasteboard: NSPasteboard) -> Bool {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return false }
        let text = (storage.string as NSString).substring(with: range)
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

// 整个日志共用一个文本存储，使系统的拖选、全选与复制可跨越记录边界。
struct ConsoleLogView: NSViewRepresentable {
    let entries: [Entry]
    let format: WireFormat
    let language: InterfaceLanguage
    let follow: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let view = ConsoleTextView(frame: scroll.contentView.bounds)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.backgroundColor = NSColor(srgbRed: 0.075, green: 0.105, blue: 0.14, alpha: 1)
        view.textContainerInset = NSSize(width: 10, height: 12)
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .white
        view.setAccessibilityLabel(language.text("收发日志"))
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        context.coordinator.update(view, entries: entries, format: format, language: language, follow: follow)
    }

    final class Coordinator {
        private var firstID: Int?
        private var lastID: Int?
        private var lengths: [Int] = []
        private var previousFormat: WireFormat?
        private var languageCode: String?
        private var previousFollow = false
        private let stamp: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()
        private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        func update(_ view: NSTextView, entries: [Entry], format: WireFormat, language: InterfaceLanguage, follow: Bool) {
            guard let storage = view.textStorage else { return }
            let rebuild = format != previousFormat || languageCode != language.code
            let followEnabled = follow && !previousFollow
            previousFollow = follow
            let first = entries.first?.id
            let last = entries.last?.id
            if rebuild || first != firstID || last != lastID {
                let selection = view.selectedRange()
                // 缓存按递增的连续记录编号从头淘汰，长度使用 AppKit 的 UTF-16 单位。
                let dropCount = rebuild ? lengths.count : min(lengths.count, max(0, (first ?? 0) - (firstID ?? 0)))
                let removed = (entries.isEmpty || rebuild) ? storage.length : lengths.prefix(dropCount).reduce(0, +)
                storage.beginEditing()
                if removed > 0 { storage.deleteCharacters(in: NSRange(location: 0, length: removed)) }
                if entries.isEmpty || rebuild { lengths.removeAll(keepingCapacity: true) }
                else if dropCount > 0 { lengths.removeFirst(dropCount) }
                for entry in entries.dropFirst(lengths.count) {
                    let line = attributedLine(entry, format: format, language: language)
                    lengths.append(line.length)
                    storage.append(line)
                }
                storage.endEditing()
                let start = rebuild ? 0 : min(storage.length, max(0, selection.location - removed))
                let end = rebuild ? 0 : min(storage.length, max(0, NSMaxRange(selection) - removed))
                let preserved = NSRange(location: start, length: end - start)
                if view.selectedRange() != preserved { view.setSelectedRange(preserved) }
                firstID = first
                lastID = last
                previousFormat = format
                languageCode = language.code
                if rebuild { view.setAccessibilityLabel(language.text("收发日志")) }
            } else if !followEnabled { return }

            if follow && view.selectedRange().length == 0 {
                view.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
            }
        }

        private func attributedLine(_ entry: Entry, format: WireFormat, language: InterfaceLanguage) -> NSAttributedString {
            let line = NSMutableAttributedString()
            func append(_ text: String, color: NSColor) {
                line.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
            }
            let muted = NSColor(white: 0.68, alpha: 1)
            append(stamp.string(from: entry.time) + "  ", color: muted)
            append(entry.rx ? "RX  " : "TX  ", color: entry.rx ? .systemMint : .systemOrange)
            if entry.source.hasPrefix("TCP ") { append(language.source(entry.source) + "  ", color: muted) }
            let payload = format == .hex ? entry.hex : entry.text
            append(payload, color: .white)
            if !payload.hasSuffix("\n") && !payload.hasSuffix("\r\n") { append("\n", color: .white) }
            return line
        }
    }
}
