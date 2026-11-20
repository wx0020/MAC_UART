import Darwin
import Foundation

enum Parity: String, Codable, CaseIterable {
    case none = "无", odd = "奇校验", even = "偶校验"
}

enum FlowControl: String, Codable, CaseIterable {
    case none = "无", hardware = "RTS/CTS", software = "XON/XOFF"
}

struct SerialSettings: Codable {
    static let rates = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
    var baud = 115200
    var bits = 8
    var parity = Parity.none
    var stops = 1
    var flow = FlowControl.none

    var summary: String {
        let letter = parity == .none ? "N" : (parity == .odd ? "O" : "E")
        return "\(baud) · \(bits)\(letter)\(stops)" + (flow == .none ? "" : " · " + flow.rawValue)
    }

    func apply(to config: inout termios) -> Bool {
        let sizes = [CS5, CS6, CS7, CS8]
        guard (5...8).contains(bits), (1...2).contains(stops), Self.rates.contains(baud) else {
            errno = EINVAL
            return false
        }
        cfmakeraw(&config)
        config.c_cflag = tcflag_t(sizes[bits - 5] | CREAD | CLOCAL)
        config.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY | INPCK | IGNPAR)
        if parity != .none {
            config.c_cflag |= tcflag_t(PARENB)
            config.c_iflag |= tcflag_t(INPCK)
        }
        if parity == .odd { config.c_cflag |= tcflag_t(PARODD) }
        if stops == 2 { config.c_cflag |= tcflag_t(CSTOPB) }
        if flow == .hardware { config.c_cflag |= tcflag_t(CCTS_OFLOW | CRTS_IFLOW) }
        if flow == .software { config.c_iflag |= tcflag_t(IXON | IXOFF) }
        return cfsetspeed(&config, speed_t(baud)) == 0
    }
}
