import AppKit
import Foundation
import Network

/// Local control API for the HM Remote iPhone companion.
/// Playback remains entirely inside CassettePlayer; this service only exposes state and commands.
final class HMRemoteServer: NSObject {

    private weak var audio: AudioPlayer?
    private var listener: NWListener?
    private let queue = DispatchQueue.main
    private let port: NWEndpoint.Port = 8766
    private let pairingCode = String(format: "%06d", Int.random(in: 0...999_999))
    private let accessToken: String
    private var statusItem: NSStatusItem?
    private var statusMessageItem: NSMenuItem?

    private static let tokenDefaultsKey = "HMRemote.AccessToken"

    init(audio: AudioPlayer) {
        self.audio = audio
        if let saved = UserDefaults.standard.string(forKey: Self.tokenDefaultsKey), !saved.isEmpty {
            accessToken = saved
        } else {
            let generated = UUID().uuidString
            UserDefaults.standard.set(generated, forKey: Self.tokenDefaultsKey)
            accessToken = generated
        }
        super.init()
    }

    func start() {
        guard listener == nil else { return }

        do {
            let newListener = try NWListener(using: .tcp, on: port)
            newListener.service = NWListener.Service(name: "Mayak-233", type: "_hmremote._tcp")
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            // Keep the menu visible even if the listener fails, so the failure is diagnosable.
            installStatusItem()
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.updateStatusMessage("Сервер запущен · порт \(self.port.rawValue)")
                    NSLog("HM Remote API is listening on port %d.", Int(self.port.rawValue))
                case .failed(let error):
                    self.updateStatusMessage("Ошибка сервера: \(error.localizedDescription)")
                    NSLog("HM Remote server failed to start: %@", error.localizedDescription)
                case .cancelled:
                    self.updateStatusMessage("Сервер остановлен")
                default:
                    break
                }
            }
            listener = newListener
            newListener.start(queue: queue)
        } catch {
            NSLog("Cannot start HM Remote API: %@", error.localizedDescription)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "HM Remote"
        let menu = NSMenu()
        let heading = NSMenuItem(title: "HM Remote · Маяк-233", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        let codeItem = NSMenuItem(title: "Код подключения: \(pairingCode)", action: nil, keyEquivalent: "")
        codeItem.isEnabled = false
        menu.addItem(codeItem)

        let portItem = NSMenuItem(title: "Порт: \(port.rawValue)", action: nil, keyEquivalent: "")
        portItem.isEnabled = false
        menu.addItem(portItem)

        let statusMessage = NSMenuItem(title: "Запуск сервера…", action: nil, keyEquivalent: "")
        statusMessage.isEnabled = false
        menu.addItem(statusMessage)
        statusMessageItem = statusMessage
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Закрыть HM Remote API", action: #selector(stopFromMenu), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    private func updateStatusMessage(_ message: String) {
        statusMessageItem?.title = message
    }

    @objc private func stopFromMenu() {
        listener?.cancel()
        listener = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let request = Self.parseCompleteRequest(buffer) {
                self.respond(to: request, on: connection)
                return
            }

            if error != nil || isComplete || buffer.count > 1_000_000 {
                self.send(status: 400, contentType: "application/json", body: Data(#"{"error":"bad_request"}"#.utf8), on: connection)
                return
            }
            self.receiveRequest(on: connection, accumulated: buffer)
        }
    }

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private static func parseCompleteRequest(_ data: Data) -> Request? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator),
              let headerText = String(data: data[..<range.lowerBound], encoding: .utf8) else {
            return nil
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = range.upperBound
        let expectedBodyLength = Int(headers["content-length"] ?? "0") ?? 0
        guard data.count - bodyStart >= expectedBodyLength else { return nil }

        let body = data.subdata(in: bodyStart..<(bodyStart + expectedBodyLength))
        return Request(method: String(parts[0]), path: String(parts[1]), headers: headers, body: body)
    }

    private func respond(to request: Request, on connection: NWConnection) {
        if request.method == "POST", request.path == "/api/pair" {
            guard
                let json = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
                let code = json["code"] as? String,
                code == pairingCode
            else {
                sendJSON(["error": "invalid_pairing_code"], status: 401, on: connection)
                return
            }
            sendJSON(["token": accessToken, "device": "Mayak-233"], status: 200, on: connection)
            return
        }

        guard authorized(request) else {
            sendJSON(["error": "unauthorized"], status: 401, on: connection)
            return
        }

        if request.method == "GET", request.path == "/api/state" {
            sendJSON(statePayload(), status: 200, on: connection)
            return
        }

        if request.method == "GET", request.path == "/api/artwork" {
            sendArtwork(on: connection)
            return
        }

        if request.method == "POST", request.path == "/api/command" {
            handleCommand(request.body, on: connection)
            return
        }

        sendJSON(["error": "not_found"], status: 404, on: connection)
    }

    private func authorized(_ request: Request) -> Bool {
        guard let header = request.headers["authorization"] else { return false }
        let prefix = "Bearer "
        guard header.lowercased().hasPrefix(prefix.lowercased()) else { return false }
        return String(header.dropFirst(prefix.count)) == accessToken
    }

    private func statePayload() -> [String: Any] {
        let track = audio?.currentTrack
        let title = track?.taggedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "device": "Mayak-233",
            "title": (title?.isEmpty == false ? title! : (track?.title ?? "")),
            "artist": track?.artist.isEmpty == false ? (track?.artist ?? "") : "Неизвестный исполнитель",
            "album": track?.album ?? "",
            "isPlaying": audio?.isPlaying ?? false,
            "currentTime": audio?.currentTime ?? 0,
            "duration": audio?.duration ?? 0,
            "hasArtwork": track?.artwork != nil
        ]
    }

    private func handleCommand(_ body: Data, on connection: NWConnection) {
        guard
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let command = json["command"] as? String,
            let audio
        else {
            sendJSON(["error": "invalid_command"], status: 400, on: connection)
            return
        }

        switch command {
        case "playPause":
            audio.togglePlayPause()
        case "next":
            audio.next()
        case "previous":
            audio.previous()
        case "seek":
            guard let seconds = json["seconds"] as? Double else {
                sendJSON(["error": "missing_seconds"], status: 400, on: connection)
                return
            }
            audio.seek(to: seconds)
        default:
            sendJSON(["error": "unknown_command"], status: 400, on: connection)
            return
        }

        sendJSON(["ok": true], status: 200, on: connection)
    }

    private func sendArtwork(on connection: NWConnection) {
        if let artwork = audio?.currentTrack?.artwork {
            send(status: 200, contentType: "application/octet-stream", body: artwork, on: connection)
            return
        }

        guard
            let url = Bundle.module.url(forResource: "CassettePlayerPlaceholder", withExtension: "png"),
            let data = try? Data(contentsOf: url)
        else {
            send(status: 404, contentType: "application/json", body: Data(#"{"error":"artwork_unavailable"}"#.utf8), on: connection)
            return
        }
        send(status: 200, contentType: "image/png", body: data, on: connection)
    }

    private func sendJSON(_ object: [String: Any], status: Int, on connection: NWConnection) {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else {
            send(status: 500, contentType: "application/json", body: Data(#"{"error":"serialization_failed"}"#.utf8), on: connection)
            return
        }
        send(status: status, contentType: "application/json; charset=utf-8", body: body, on: connection)
    }

    private func send(status: Int, contentType: String, body: Data, on connection: NWConnection) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        default: reason = "Internal Server Error"
        }
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
