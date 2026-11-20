import Foundation
import Network

struct TCPPeer: Identifiable, Equatable {
    let id: UUID
    let address: String
}

enum TCPEvent {
    case listening, joined(TCPPeer), left(UUID, String), stopped(String)
    case received(TCPPeer, Data), sent(TCPPeer, Data), sendFailed(String)
}

// 所有入口和网络回调在主队列运行。每次回调核对连接身份，忽略旧会话的取消通知。
final class TCPTransport {
    var event: (TCPEvent) -> Void = { _ in }
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]

    func listen(port: NWEndpoint.Port) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let server = try NWListener(using: params, on: port)
            listener = server
            server.stateUpdateHandler = { [weak self, weak server] state in
                guard let self, let server, self.listener === server else { return }
                switch state {
                case .ready: self.event(.listening)
                case .failed(let error), .waiting(let error): self.stop(error.localizedDescription)
                default: break
                }
            }
            server.newConnectionHandler = { [weak self, weak server] client in
                guard let self, let server, self.listener === server else { client.cancel(); return }
                self.attach(client)
            }
            server.start(queue: .main)
        } catch { stop(error.localizedDescription) }
    }

    func connect(host: String, port: NWEndpoint.Port) {
        attach(NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp))
    }

    private func attach(_ connection: NWConnection) {
        let peer = TCPPeer(id: UUID(), address: String(describing: connection.endpoint))
        connections[peer.id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connections[peer.id] === connection else { return }
            switch state {
            case .ready:
                self.event(.joined(peer))
                self.receive(from: connection, peer: peer)
            case .failed(let error), .waiting(let error):
                self.remove(peer, reason: error.localizedDescription)
            default: break
            }
        }
        connection.start(queue: .main)
    }

    private func receive(from connection: NWConnection, peer: TCPPeer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] bytes, _, finished, error in
            guard let self, let connection, self.connections[peer.id] === connection else { return }
            if let bytes, !bytes.isEmpty { self.event(.received(peer, bytes)) }
            if finished || error != nil {
                self.remove(peer, reason: error?.localizedDescription ?? "对端已断开")
            } else {
                self.receive(from: connection, peer: peer)
            }
        }
    }

    func send(_ data: Data, to id: UUID) {
        guard let connection = connections[id] else { event(.sendFailed("对端已断开")); return }
        let peer = TCPPeer(id: id, address: String(describing: connection.endpoint))
        connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self, let connection, self.connections[id] === connection else { return }
            if let error { self.remove(peer, reason: error.localizedDescription) }
            else { self.event(.sent(peer, data)) }
        })
    }

    private func remove(_ peer: TCPPeer, reason: String) {
        connections.removeValue(forKey: peer.id)?.cancel()
        if listener == nil { event(.stopped(reason)) }
        else { event(.left(peer.id, reason)) }
    }

    func stop(_ reason: String = "TCP 已停止") {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        event(.stopped(reason))
    }
}
