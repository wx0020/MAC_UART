import Foundation
import Darwin

enum PortEvent {
    case connected, closed(InterfaceMessage), received(Data, Date), sent(Data, Date), sendFinished
}

// 描述符、待发送数据和定时器均由同一队列管理，关闭后才能重新打开。
final class SerialPort: @unchecked Sendable {
    private let queue = DispatchQueue(label: "uart.io", qos: .userInitiated)
    private var fd: Int32 = -1
    private var saved = termios()
    private var timer: DispatchSourceTimer?
    private var pending = Data()
    private var offset = 0
    var event: (PortEvent) -> Void = { _ in }

    func connect(_ path: String, settings: SerialSettings) {
        queue.async { [self] in
            guard fd < 0 else { return }
            fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard fd >= 0 else { fail("打开失败"); return }
            guard tcgetattr(fd, &saved) == 0 else {
                let message = String(cString: strerror(errno))
                Darwin.close(fd)
                fd = -1
                event(.closed(InterfaceMessage("读取参数失败：%@", message)))
                return
            }
            var config = saved
            guard settings.apply(to: &config),
                  tcsetattr(fd, TCSANOW, &config) == 0,
                  ioctl(fd, TIOCEXCL) == 0 else { fail("配置失败"); return }
            event(.connected)
            let clock = DispatchSource.makeTimerSource(queue: queue)
            clock.schedule(deadline: .now(), repeating: .milliseconds(20))
            clock.setEventHandler { [weak self] in self?.tick() }
            timer = clock
            clock.resume()
        }
    }

    func disconnect() {
        queue.async { self.close("串口已关闭") }
    }

    func send(_ bytes: Data) {
        queue.async { [self] in
            guard fd >= 0, pending.isEmpty else { return }
            pending = bytes
            offset = 0
            tick()
        }
    }

    private func fail(_ prefix: String) {
        close(InterfaceMessage(prefix + "：%@", String(cString: strerror(errno))))
    }

    private func close(_ reason: InterfaceMessage) {
        timer?.cancel()
        timer = nil
        if fd >= 0 {
            _ = tcsetattr(fd, TCSANOW, &saved)
            Darwin.close(fd)
            fd = -1
        }
        pending.removeAll()
        offset = 0
        event(.closed(reason))
    }

    private func tick() {
        guard fd >= 0 else { return }
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN | (pending.isEmpty ? 0 : POLLOUT)), revents: 0)
        let count = poll(&descriptor, 1, 0)
        if count < 0 { if errno != EINTR { fail("查询串口失败") }; return }
        if descriptor.revents & Int16(POLLIN) != 0 {
            var buffer = [UInt8](repeating: 0, count: 65536)
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n > 0 { event(.received(Data(buffer.prefix(n)), Date())) }
            else if n == 0 { close("设备已断开"); return }
            else if errno != EAGAIN && errno != EINTR { fail("接收失败"); return }
        }
        if descriptor.revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
            close("设备已断开")
            return
        }
        if descriptor.revents & Int16(POLLOUT) != 0 && !pending.isEmpty {
            let n = pending.withUnsafeBytes {
                Darwin.write(fd, $0.baseAddress!.advanced(by: offset), pending.count - offset)
            }
            if n > 0 {
                event(.sent(pending.subdata(in: offset..<offset+n), Date()))
                offset += n
                if offset == pending.count {
                    pending.removeAll()
                    offset = 0
                    event(.sendFinished)
                }
            } else if n < 0 && errno != EAGAIN && errno != EINTR { fail("发送失败") }
        }
    }
}
