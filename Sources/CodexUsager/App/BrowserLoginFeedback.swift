import AppKit
import Network

/// A short-lived loopback page, separate from the official OAuth callback server.
/// It receives no OAuth codes, account details, cookies or credentials.
@MainActor final class BrowserLoginFeedback {
    private var pending: CheckedContinuation<URL, any Error>?
    private var listener: NWListener?
    private var expiry: Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]

    func show(success: Bool, message: String) async throws {
        stop()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let body = Self.page(success: success, message: message)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                guard let self, let listener, self.listener === listener else { return }
                if case .ready = state, let port = listener.port,
                   let url = URL(string: "http://127.0.0.1:\(port.rawValue)/") {
                    self.pending?.resume(returning: url); self.pending = nil
                } else if case .failed = state {
                    self.pending?.resume(throwing: CocoaError(.fileReadUnknown)); self.pending = nil
                    self.stop()
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection, body: body) }
        }
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            self?.stop()
        }
        let url = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                listener.start(queue: .main)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.stop() } }
        try Task.checkCancellation()
        guard NSWorkspace.shared.open(url) else { stop(); throw CocoaError(.fileReadUnknown) }
    }
    private func accept(_ connection: NWConnection, body: String) {
        guard connections.count < 8 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, body: body, buffered: Data())
    }
    private func receive(_ connection: NWConnection, id: UUID, body: String, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: max(1, 4096 - buffered.count)) { [weak self] data, _, complete, error in
            let bytes = buffered + (data ?? Data())
            let text = String(data: bytes, encoding: .utf8)
            let firstLine = text?.components(separatedBy: "\r\n").first
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { connection.cancel(); return }
                if bytes.count < 4096, text?.contains("\r\n\r\n") != true, !complete, error == nil {
                    self.receive(connection, id: id, body: body, buffered: bytes)
                    return
                }
                let valid = text?.contains("\r\n\r\n") == true && (firstLine == "GET / HTTP/1.1" || firstLine == "GET / HTTP/1.0")
                let content = valid ? body : "页面不存在。"
                let bytes = Data(content.utf8)
                let header = "HTTP/1.1 \(valid ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(header.utf8) + bytes, completion: .contentProcessed { [weak self] _ in
                    connection.cancel()
                    Task { @MainActor in self?.connections.removeValue(forKey: id) }
                })
            }
        }
    }
    private static func page(success: Bool, message: String) -> String {
        let text = message.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return """
        <!doctype html><html lang="zh-Hans"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>CodexUsager \(success ? "已连接" : "连接未完成")</title>
        <style>:root{color-scheme:light dark}body{font:17px -apple-system,BlinkMacSystemFont,sans-serif;margin:0;background:Canvas;color:CanvasText}main{max-width:480px;margin:15vh auto;padding:32px}h1{font-size:28px;font-weight:600}p{line-height:1.7;color:GrayText}a{color:LinkText} .status{font-weight:600;color:\(success ? "#248447" : "#b36b00")}</style>
        <main><h1>CodexUsager \(success ? "已连接" : "连接未完成")</h1>
        <div class="status">\(success ? "✓ 已连接" : "连接失败")</div><p>\(text)</p>
        <a href="codexusager://\(success ? "open" : "login")">\(success ? "返回应用" : "重新登录")</a>
        <p>此页面仅显示本机连接结果，不接收或保存账户信息。</p></main></html>
        """
    }
    func stop() {
        pending?.resume(throwing: CancellationError()); pending = nil
        expiry?.cancel(); expiry = nil
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }
}
