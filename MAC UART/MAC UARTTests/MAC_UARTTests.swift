import Testing
@testable import MAC_UART

struct MAC_UARTTests {
    @Test func draftByteCountMatchesWirePayload() {
        #expect(Command(input: "电", ending: "\r\n").byteCount == 5)
        #expect(Command(ending: "\r").byteCount == 1)
        #expect(Command(input: "01 aA\nFF", format: .hex, ending: "\r\n").byteCount == 3)
        #expect(Command(input: "  ", format: .hex).byteCount == 0)
        #expect(Command(input: "F", format: .hex).byteCount == nil)
        #expect(Command(input: "G0", format: .hex).byteCount == nil)
    }
}
