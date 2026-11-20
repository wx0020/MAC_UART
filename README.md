# MAC UART

English · [简体中文](README.zh-CN.md)

MAC UART is a native macOS serial and TCP debugging tool for working with embedded devices, USB-to-serial adapters, and card readers. Send a binary command, inspect the reply in HEX, and save the command for the next device. For longer tests, run a command sequence and record traffic directly to disk.

## Connect a device

| Mode | How to connect |
| --- | --- |
| Serial | Select a detected `/dev/cu.*` port and its baud rate, then click **Open port**. The default is 115200 baud, 8 data bits, no parity, 1 stop bit, and no flow control. |
| TCP Client | Enter the server’s IP address or hostname and port, then click **Connect**. |
| TCP Server | Enter a local port and click **Start listening**. When multiple clients connect, choose the recipient under **Send to**. The traffic log identifies each peer. |

Open **Serial → Serial settings…** (⌘,) to change baud rate, data bits (5–8), parity (none, odd, even), stop bits (1 or 2), and flow control (none, RTS/CTS, XON/XOFF). Close the serial port before changing its settings. The app saves the settings for the next connection.

## Send and inspect data

- Choose **Text** to send UTF-8 with an optional CR, LF, or CR LF ending. Choose **HEX** to send raw bytes. For example, entering `41 0D 0A` sends three bytes. Click **Send** or press ⌘Return.
- The traffic log shows millisecond timestamps, RX/TX direction, and byte counters. Its Text/HEX selector works independently of the send format and also applies to existing entries.
- Use **Save as command** to keep a named command with its format and line ending. Click a saved command to send it over the active connection.

## Repeat a command or run a sequence

Open **Automatic sending…** in the send area. **Timed send** repeats the current input. **Command sequence** sends checked quick commands from top to bottom. Use the arrows to change the order and set an optional interval for each command.

For example, to run a device query followed by a status read 100 times, save both commands, check them in that order, set the default interval to `1000` ms, and enter `100` rounds. Each delay starts when the preceding send completes. A round count of `0` runs until stopped. Click **Stop sequence** to end the run. Disconnecting the active device or TCP peer also stops the sequence.

## Export or record traffic

| Action | What gets written |
| --- | --- |
| **Export log…** (⇧⌘E) | Saves the entries currently in the display buffer as UTF-8 text, using the selected Text or HEX view. The buffer holds up to 3,000 entries and normally about 1 MiB of payload. |
| **Record traffic…** in the status bar | Choose a folder to start recording new traffic. Recording keeps the display format selected at the start and rolls over to numbered files at about 10 MiB each. Clearing the display does not interrupt recording. Click **Stop recording** to finish. |

Both outputs include the date, millisecond timestamp, direction, and serial path or TCP peer. A HEX log entry looks like this:

```text
[2026-11-19 10:42:15.083] TX [/dev/cu.usbserial-01] 41 0D 0A
```

## Run or build

The deployment target is **macOS 14 or later**. The locally built app targets **Apple silicon**. If you have the packaged copy, open `dist/MAC_UART.app`. To build from source, use Xcode with macOS support. This project has been built with Xcode 27.2.

From the project root, run:

```bash
xcodebuild -project "MAC UART/MAC UART.xcodeproj" -scheme "MAC UART" \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
open "build/Build/Products/Release/MAC UART.app"
```

The interface follows the system language by default. Use **Language** in the menu bar to switch between English and Simplified Chinese.

## Verification

Virtual serial-port tests covered text and binary transfers, reconnection, timed sends, sequence order, stopping on disconnect, and continuous recording beyond the display buffer. Physical USB serial hardware and end-to-end TCP transfers still need verification.
