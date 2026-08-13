import Foundation
import Network

/// Minimal loopback HTTP server mimicking Ollama's POST /api/chat for tests.
final class StubOllamaServer {
    static let rewrittenText = "Rewritten stub output text."

    private(set) var baseURL: String = ""
    private(set) var lastModel: String?
    private(set) var lastPrompt: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "stub-ollama")

    init() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        let ready = DispatchSemaphore(value: 0)
        var startupError: Error?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port {
                    self.baseURL = "http://127.0.0.1:\(port.rawValue)"
                }
                ready.signal()
            case .failed(let error):
                startupError = error
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
        ready.wait()

        if let startupError {
            throw startupError
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self.captureRequest(request)
            let body: [String: Any] = [
                "message": ["role": "assistant", "content": StubOllamaServer.rewrittenText],
                "done": true,
            ]
            let json = try! JSONSerialization.data(withJSONObject: body)
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n"
            var payload = Data(response.utf8)
            payload.append(json)
            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func captureRequest(_ raw: String) {
        guard let bodyRange = raw.range(of: "\r\n\r\n") else { return }
        let body = String(raw[bodyRange.upperBound...])
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        lastModel = obj["model"] as? String
        if let messages = obj["messages"] as? [[String: Any]] {
            lastPrompt = messages.first?["content"] as? String
        }
    }
}
