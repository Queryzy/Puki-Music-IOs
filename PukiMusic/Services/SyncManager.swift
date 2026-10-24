import Foundation
import Combine
import CryptoKit
import UIKit

enum SyncConnectionState {
    case disconnected
    case connecting
    case synced
    case error(String)
}

struct SyncEventPayload: Codable {
    let id: String
    let action: String
    let timestamp: Int64
    let data: [String: AnyCodable]
}

// Helper for dynamic JSON serialization/deserialization
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int64.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int64 as Int64:
            try container.encode(int64)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    private let defaults = UserDefaults.standard
    private let kPrefVaultId = "puki_sync_vault_id"
    private let kPrefSyncSecret = "puki_sync_secret"
    private let kPrefRelayUrl = "puki_sync_relay_url"
    private let kPrefLastPulledSeq = "puki_sync_last_seq"
    private let kPrefOutbox = "puki_sync_outbox"

    private let defaultRelayUrl = ""

    @Published var isSyncEnabled: Bool = false
    @Published var connectionState: SyncConnectionState = .disconnected
    @Published var lastSyncTimestamp: Int64 = 0
    @Published var currentVaultId: String = ""

    private var derivedKeys: SyncDerivedKeys?
    private var isSyncing = false
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?

    private init() {
        loadSettings()
        setupForegroundObserver()
    }

    private func loadSettings() {
        let vaultId = defaults.string(forKey: kPrefVaultId) ?? ""
        let secret = defaults.string(forKey: kPrefSyncSecret) ?? ""
        let relay = defaults.string(forKey: kPrefRelayUrl) ?? ""
        if !vaultId.isEmpty && !secret.isEmpty && !relay.isEmpty {
            self.currentVaultId = vaultId
            do {
                self.derivedKeys = try SyncCrypto.deriveKeys(syncSecretHex: secret)
                self.isSyncEnabled = true
                self.connectionState = .synced
                startPolling()
            } catch {
                self.connectionState = .error("Gagal derivasi kunci: \(error.localizedDescription)")
            }
        }
    }

    private func setupForegroundObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleAppForeground() {
        guard isSyncEnabled else { return }
        triggerSyncNow()
    }

    func getRelayUrl() -> String {
        return defaults.string(forKey: kPrefRelayUrl) ?? ""
    }

    func setRelayUrl(_ url: String) {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        defaults.set(clean, forKey: kPrefRelayUrl)
    }

    func getPairingUri() -> String {
        guard let vaultId = defaults.string(forKey: kPrefVaultId),
              let secret = defaults.string(forKey: kPrefSyncSecret) else {
            return ""
        }
        let relay = getRelayUrl()
        return "puki://sync?relay=\(relay.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? relay)&vault=\(vaultId)&key=\(secret)"
    }

    func initializeNewVault(customUrl: String? = nil) throws -> String {
        let targetRelay = (customUrl ?? getRelayUrl()).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !targetRelay.isEmpty else {
            throw NSError(domain: "PukiSync", code: 400, userInfo: [NSLocalizedDescriptionKey: "URL Relay belum diisi! Silakan masukkan URL relay server terlebih dahulu."])
        }
        let newVaultId = UUID().uuidString.lowercased()
        let newSecret = SyncCrypto.generateSyncSecret()
        let keys = try SyncCrypto.deriveKeys(syncSecretHex: newSecret)

        defaults.set(newVaultId, forKey: kPrefVaultId)
        defaults.set(newSecret, forKey: kPrefSyncSecret)
        defaults.set(targetRelay, forKey: kPrefRelayUrl)
        defaults.set(0, forKey: kPrefLastPulledSeq)

        self.currentVaultId = newVaultId
        self.derivedKeys = keys
        self.isSyncEnabled = true
        self.connectionState = .connecting

        Task {
            await self.registerVaultOnServer(vaultId: newVaultId, authVerifier: keys.authVerifierHex)
            await self.syncDelta()
        }

        startPolling()
        return getPairingUri()
    }

    func parseAndApplyPairingUri(_ uriString: String) -> Bool {
        guard let url = URL(string: uriString), url.scheme == "puki", url.host == "sync" else {
            return false
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return false
        }

        var vaultId: String?
        var secret: String?
        var relay: String?

        for item in queryItems {
            if item.name == "vault" { vaultId = item.value }
            if item.name == "key" { secret = item.value }
            if item.name == "relay" { relay = item.value }
        }

        guard let vId = vaultId, !vId.isEmpty,
              let sec = secret, sec.count == 64 else {
            return false
        }

        let targetRelay = (relay ?? getRelayUrl()).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !targetRelay.isEmpty else {
            return false
        }

        do {
            let keys = try SyncCrypto.deriveKeys(syncSecretHex: sec)
            defaults.set(vId, forKey: kPrefVaultId)
            defaults.set(sec, forKey: kPrefSyncSecret)
            defaults.set(targetRelay, forKey: kPrefRelayUrl)
            defaults.set(0, forKey: kPrefLastPulledSeq)

            self.currentVaultId = vId
            self.derivedKeys = keys
            self.isSyncEnabled = true
            self.connectionState = .connecting

            triggerSyncNow()
            startPolling()
            return true
        } catch {
            return false
        }
    }

    func disableSync() {
        defaults.removeObject(forKey: kPrefVaultId)
        defaults.removeObject(forKey: kPrefSyncSecret)
        defaults.removeObject(forKey: kPrefLastPulledSeq)
        defaults.removeObject(forKey: kPrefOutbox)

        self.isSyncEnabled = false
        self.currentVaultId = ""
        self.derivedKeys = nil
        self.connectionState = .disconnected
        stopPolling()
    }

    func queueEvent(action: String, data: [String: Any]) {
        guard isSyncEnabled else { return }
        let event = SyncEventPayload(
            id: UUID().uuidString.lowercased(),
            action: action,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            data: data.mapValues { AnyCodable($0) }
        )

        var outbox = loadOutbox()
        outbox.append(event)
        saveOutbox(outbox)

        triggerSyncNow()
    }

    func triggerSyncNow() {
        guard isSyncEnabled, !isSyncing else { return }
        Task {
            await self.syncDelta()
        }
    }

    private func startPolling() {
        stopPolling()
        DispatchQueue.main.async {
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 35.0, repeats: true) { [weak self] _ in
                self?.triggerSyncNow()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func syncDelta() async {
        guard !isSyncing else { return }
        isSyncing = true

        defer { isSyncing = false }

        await pushOutbox()
        await pullRemoteDelta()

        DispatchQueue.main.async {
            self.lastSyncTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
            self.connectionState = .synced
        }
    }

    private func pushOutbox() async {
        var outbox = loadOutbox()
        guard !outbox.isEmpty,
              !getRelayUrl().isEmpty,
              let keys = derivedKeys,
              let vaultId = defaults.string(forKey: kPrefVaultId) else {
            return
        }

        let batch = Array(outbox.prefix(20))
        guard let jsonData = try? JSONEncoder().encode(batch),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            return
        }

        do {
            let ciphertext = try SyncCrypto.encrypt(plaintext: jsonStr, key: keys.encKey)
            let path = "/api/v1/sync/push"
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let bodyDict: [String: Any] = [
                "vault_id": vaultId,
                "ciphertext": ciphertext
            ]
            guard let reqBodyData = try? JSONSerialization.data(withJSONObject: bodyDict),
                  let reqBodyStr = String(data: reqBodyData, encoding: .utf8) else {
                return
            }

            let signature = SyncCrypto.signRequest(
                authKey: keys.authKey,
                vaultId: vaultId,
                timestamp: now,
                body: reqBodyStr
            )

            let urlStr = "\(getRelayUrl())\(path)"
            guard let url = URL(string: urlStr) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(vaultId, forHTTPHeaderField: "X-Vault-ID")
            request.setValue(String(now), forHTTPHeaderField: "X-Timestamp")
            request.setValue(signature, forHTTPHeaderField: "X-Signature")
            request.httpBody = reqBodyData

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                // Remove synced batch
                outbox.removeFirst(batch.count)
                saveOutbox(outbox)
            }
        } catch {
            print("[SyncManager] Push error: \(error)")
        }
    }

    private func pullRemoteDelta() async {
        guard !getRelayUrl().isEmpty,
              let keys = derivedKeys,
              let vaultId = defaults.string(forKey: kPrefVaultId) else {
            return
        }

        let lastSeq = defaults.integer(forKey: kPrefLastPulledSeq)
        let path = "/api/v1/sync/pull"
        let fullPathWithQuery = "\(path)?vault_id=\(vaultId)&since_seq=\(lastSeq)&limit=50"
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        let signature = SyncCrypto.signRequest(
            authKey: keys.authKey,
            vaultId: vaultId,
            timestamp: now,
            body: ""
        )

        let urlStr = "\(getRelayUrl())\(fullPathWithQuery)"
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(vaultId, forHTTPHeaderField: "X-Vault-ID")
        request.setValue(String(now), forHTTPHeaderField: "X-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let events = json["events"] as? [[String: Any]] else {
                return
            }

            var maxSeq = lastSeq
            for ev in events {
                if let seq = ev["seq"] as? Int, seq > maxSeq {
                    maxSeq = seq
                }
                if let ciphertext = ev["ciphertext"] as? String {
                    if let plaintext = try? SyncCrypto.decrypt(ciphertextBase64: ciphertext, key: keys.encKey) {
                        DispatchQueue.main.async {
                            self.applyDecryptedEvents(plaintext)
                        }
                    }
                }
            }

            defaults.set(maxSeq, forKey: kPrefLastPulledSeq)
        } catch {
            print("[SyncManager] Pull error: \(error)")
        }
    }

    private func applyDecryptedEvents(_ jsonStr: String) {
        guard let data = jsonStr.data(using: .utf8),
              let list = try? JSONDecoder().decode([SyncEventPayload].self, from: data) else {
            return
        }

        for item in list {
            LocalMusicStore.shared.applyRemoteSyncEvent(action: item.action, data: item.data.mapValues { $0.value })
        }
    }

    private func registerVaultOnServer(vaultId: String, authVerifier: String) async {
        do {
            let chalUrl = URL(string: "\(getRelayUrl())/api/v1/vault/challenge")!
            let (data, _) = try await URLSession.shared.data(from: chalUrl)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let challenge = json["challenge"] as? String else {
                return
            }

            // Solve PoW (4 leading zeros)
            var nonce: Int64 = 0
            while true {
                let testStr = "\(challenge):\(nonce)"
                let hash = SyncCrypto.sha256Hex(testStr)
                if hash.hasPrefix("0000") {
                    break
                }
                nonce += 1
            }

            // POST /api/v1/vault/init
            let initUrl = URL(string: "\(getRelayUrl())/api/v1/vault/init")!
            var req = URLRequest(url: initUrl)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let initBody: [String: Any] = [
                "vault_id": vaultId,
                "auth_verifier": authVerifier,
                "challenge": challenge,
                "nonce": String(nonce)
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: initBody)

            let (_, res) = try await URLSession.shared.data(for: req)
            if let httpRes = res as? HTTPURLResponse, httpRes.statusCode == 200 || httpRes.statusCode == 409 {
                DispatchQueue.main.async {
                    self.connectionState = .synced
                }
            }
        } catch {
            print("[SyncManager] Registration error: \(error)")
        }
    }

    private func loadOutbox() -> [SyncEventPayload] {
        guard let data = defaults.data(forKey: kPrefOutbox),
              let list = try? JSONDecoder().decode([SyncEventPayload].self, from: data) else {
            return []
        }
        return list
    }

    private func saveOutbox(_ items: [SyncEventPayload]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: kPrefOutbox)
        }
    }
}
