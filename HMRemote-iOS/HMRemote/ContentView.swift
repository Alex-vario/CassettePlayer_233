import SwiftUI
import UIKit
import Foundation
import Combine
import Network
import Security

struct RemoteDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: Int

    var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }
}

struct RemotePlaybackState: Decodable {
    let device: String
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
    let hasArtwork: Bool
}

@MainActor
final class HMRemoteModel: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published private(set) var devices: [RemoteDevice] = []
    @Published private(set) var selectedDevice: RemoteDevice?
    @Published private(set) var playback: RemotePlaybackState?
    @Published private(set) var artwork: UIImage?
    @Published private(set) var isPairing = false
    @Published private(set) var isBusy = false
    @Published var pairingCode = ""
    @Published var manualHost = ""
    @Published var displayTime: Double = 0
    @Published var isSeeking = false
    @Published var errorMessage: String?

    private let browser = NetServiceBrowser()
    private var resolvingServices: [String: NetService] = [:]
    private var servicesByID: [String: NetService] = [:]
    private var baseURL: URL?
    private var accessToken: String?
    private var artworkIdentity = ""
    private var isBrowsing = false

    override init() {
        super.init()
        browser.delegate = self
    }

    var isConnected: Bool {
        baseURL != nil && accessToken != nil && !isPairing
    }

    func startBrowsing() {
        guard !isBrowsing else { return }
        isBrowsing = true
        browser.searchForServices(ofType: "_hmremote._tcp.", inDomain: "local.")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        errorMessage = "Поиск Маяка через Bonjour не удался. Можно подключиться по IP-адресу Mac."
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isBrowsing = false
    }

    func connectManually() {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !host.isEmpty, !host.contains("/"), !host.contains(":"), let url = URL(string: "http://\(host):8765") else {
            errorMessage = "Введите IP-адрес Mac, например 192.168.0.227."
            return
        }
        let device = RemoteDevice(id: "manual-\(host)", name: "Mayak-233", host: host, port: 8765)
        selectedDevice = device
        baseURL = url
        errorMessage = nil
        pairingCode = ""
        accessToken = Keychain.read(account: host)
        isPairing = accessToken == nil
        if !isPairing {
            Task { await refresh() }
        }
    }

    func stopBrowsing() {
        guard isBrowsing else { return }
        browser.stop()
        isBrowsing = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let key = service.name + "|" + service.domain
        resolvingServices[key] = service
        service.delegate = self
        service.resolve(withTimeout: 6)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
        guard !host.isEmpty, sender.port > 0 else { return }
        let id = sender.name + "|" + sender.domain
        let device = RemoteDevice(id: id, name: sender.name, host: host, port: sender.port)
        servicesByID[id] = sender
        if let index = devices.firstIndex(where: { $0.id == id }) {
            devices[index] = device
        } else {
            devices.append(device)
            devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let id = service.name + "|" + service.domain
        devices.removeAll { $0.id == id }
        servicesByID[id] = nil
        resolvingServices[id] = nil
        if selectedDevice?.id == id {
            disconnect()
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let id = sender.name + "|" + sender.domain
        resolvingServices[id] = nil
    }

    func connect(to device: RemoteDevice) {
        guard let url = device.baseURL else {
            errorMessage = "Не удалось определить адрес Маяка."
            return
        }
        selectedDevice = device
        baseURL = url
        errorMessage = nil
        pairingCode = ""
        accessToken = Keychain.read(account: device.host)
        isPairing = accessToken == nil
        if !isPairing {
            Task { await refresh() }
        }
    }

    func pair() async {
        guard let baseURL else { return }
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            errorMessage = "Введите шестизначный код из меню HM Remote на Mac."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/pair"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code])
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard statusCode == 200,
                  let result = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let token = result["token"] else {
                let serverMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
                if statusCode == 401 {
                    errorMessage = "Маяк отклонил код (HTTP 401: \(serverMessage ?? "unauthorized")). Убедитесь, что код взят из меню именно запущенного сейчас Маяка."
                } else if statusCode == -1 {
                    errorMessage = "Ответ Маяка не распознан. Проверьте IP-адрес и подключение к одной Wi-Fi-сети."
                } else {
                    errorMessage = "Ошибка подключения к Маяку: HTTP \(statusCode) \(serverMessage ?? "")."
                }
                return
            }

            accessToken = token
            if let host = selectedDevice?.host {
                Keychain.save(token, account: host)
            }
            isPairing = false
            errorMessage = nil
            await refresh()
        } catch {
            errorMessage = "Не удалось подключиться к Маяку: \(error.localizedDescription)"
        }
    }

    func disconnect() {
        selectedDevice = nil
        baseURL = nil
        accessToken = nil
        playback = nil
        artwork = nil
        artworkIdentity = ""
        isPairing = false
        isSeeking = false
        displayTime = 0
        errorMessage = nil
    }

    func runPolling() async {
        while !Task.isCancelled {
            if isConnected {
                await refresh()
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func refresh() async {
        guard let url = baseURL?.appendingPathComponent("api/state"),
              let accessToken else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 4
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                errorMessage = "Связь с Маяком потеряна. Проверьте, что CassettePlayer запущен."
                return
            }
            let state = try JSONDecoder().decode(RemotePlaybackState.self, from: data)
            playback = state
            if !isSeeking {
                displayTime = min(max(0, state.currentTime), max(0, state.duration))
            }
            errorMessage = nil

            let newIdentity = "\(state.title)|\(state.artist)|\(state.album)"
            if newIdentity != artworkIdentity || artwork == nil {
                artworkIdentity = newIdentity
                await refreshArtwork(token: accessToken)
            }
        } catch {
            errorMessage = "Нет связи с Маяком. Убедитесь, что Mac и iPhone в одной Wi-Fi-сети."
        }
    }

    private func refreshArtwork(token: String) async {
        guard let url = baseURL?.appendingPathComponent("api/artwork") else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 5
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return }
            artwork = image
        } catch {
            // Keep the last image if a transient artwork request fails.
        }
    }

    func sendCommand(_ command: String, seconds: Double? = nil) async {
        guard let url = baseURL?.appendingPathComponent("api/command"),
              let accessToken else { return }
        var payload: [String: Any] = ["command": command]
        if let seconds { payload["seconds"] = seconds }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.timeoutInterval = 4
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                errorMessage = "Маяк не принял команду."
                return
            }
            await refresh()
        } catch {
            errorMessage = "Не удалось отправить команду: \(error.localizedDescription)"
        }
    }

    func seekToDisplayTime() async {
        isSeeking = false
        await sendCommand("seek", seconds: displayTime)
    }

    func formattedTime(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

private enum Keychain {
    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.alexvario.HMRemote",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.alexvario.HMRemote",
            kSecAttrAccount as String: account
        ]
        let data = Data(token.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = HMRemoteModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.14), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Group {
                if model.isPairing {
                    pairingView
                } else if model.isConnected {
                    playerView
                } else {
                    devicePicker
                }
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .task {
            model.startBrowsing()
            await model.runPolling()
        }
    }

    private var devicePicker: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
            Text("HM Remote")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            Text("Пульт управления Маяком-233")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
            if model.devices.isEmpty {
                ProgressView()
                    .padding(.top, 12)
                Text("Поиск Маяка в локальной сети…")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.devices) { device in
                        Button {
                            model.connect(to: device)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .font(.title2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name)
                                        .font(.headline)
                                    Text("Подключиться к Mac")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .padding(16)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Если Маяк не найден")
                    .font(.headline)
                Text("Узнайте IP-адрес Mac в настройках Wi-Fi и введите его ниже.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 10) {
                    TextField("IP-адрес Mac, например 192.168.0.227", text: $model.manualHost)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(13)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    Button("Подключить") {
                        model.connectManually()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red.opacity(0.9)).multilineTextAlignment(.center)
            }
            Spacer()
            Text("Музыка продолжает играть на Mac. iPhone только управляет воспроизведением.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
        }
    }

    private var pairingView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 48, weight: .light))
            Text("Подключение к Маяку")
                .font(.title2.weight(.semibold))
            Text("Откройте меню HM Remote в строке меню Mac и введите шестизначный код подключения.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            TextField("000000", text: $model.pairingCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button {
                Task { await model.pair() }
            } label: {
                if model.isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Подключить").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isBusy || model.pairingCode.count != 6)
            Button("Назад") { model.disconnect() }
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
        }
    }

    private var playerView: some View {
        VStack(spacing: 18) {
            HStack {
                Button {
                    model.disconnect()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(spacing: 2) {
                    Text("СЕЙЧАС ИГРАЕТ")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(2)
                    Text(model.selectedDevice?.name ?? "Маяк-233")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .frame(width: 42, height: 42)
            }
            .padding(.top, 10)

            Spacer(minLength: 4)

            Group {
                if let artwork = model.artwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFit()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.white.opacity(0.06))
                        Image(systemName: "music.note")
                            .font(.system(size: 72, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .frame(maxWidth: 310, maxHeight: 310)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.35), radius: 22, y: 12)

            VStack(spacing: 6) {
                Text(model.playback?.title.isEmpty == false ? (model.playback?.title ?? "") : "Маяк готов к воспроизведению")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(model.playback?.artist ?? "")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                if let album = model.playback?.album, !album.isEmpty {
                    Text(album)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Slider(
                    value: $model.displayTime,
                    in: 0...max(model.playback?.duration ?? 0, 1),
                    onEditingChanged: { editing in
                        model.isSeeking = editing
                        if !editing {
                            Task { await model.seekToDisplayTime() }
                        }
                    }
                )
                .tint(.white)
                HStack {
                    Text(model.formattedTime(model.displayTime))
                    Spacer()
                    Text(model.formattedTime(model.playback?.duration ?? 0))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 38) {
                transportButton("backward.end.fill", size: 27) {
                    await model.sendCommand("previous")
                }
                transportButton(model.playback?.isPlaying == true ? "pause.fill" : "play.fill", size: 34, prominent: true) {
                    await model.sendCommand("playPause")
                }
                transportButton("forward.end.fill", size: 27) {
                    await model.sendCommand("next")
                }
            }
            .padding(.top, 4)

            if let error = model.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat,
        prominent: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: prominent ? 76 : 54, height: prominent ? 76 : 54)
                .background {
                    Circle().fill(prominent ? .white.opacity(0.18) : .white.opacity(0.07))
                }
                .overlay {
                    Circle().stroke(.white.opacity(prominent ? 0.18 : 0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
