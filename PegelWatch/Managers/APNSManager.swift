import UIKit
import Security

final class APNSManager {

    static let shared = APNSManager()
    private init() {}

    // Vapor relay service (pegelwatch-relay.felixschick.de) — not Novu directly.
    // That service holds NOVU_SECRET_KEY + APP_TOKEN server-side and makes the
    // two Novu calls: POST /v1/subscribers + PUT /v1/subscribers/{id}/credentials.
    private let relayURL = "https://pegelwatch-relay.felixschick.de/api/register-device"

    // Must match the APP_TOKEN environment variable set on the relay service.
    // Low-privilege secret: if leaked, allows registering bogus device tokens only —
    // cannot trigger notifications or read subscriber data.
    private let appToken = "bb633c8b12d69b3af52b8ad3f92aced6c5a93e24f38f036a293f08f8e2d1ac93"

    // MARK: - Subscriber ID

    /// Stable per-device identifier persisted in Keychain (survives app reinstalls).
    /// Prefers IDFV; falls back to a random UUID if IDFV is unavailable.
    var subscriberId: String {
        let key = "de.felixschick.pegelwatch.subscriber-id"
        if let stored = keychainRead(key) { return stored }
        let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        keychainWrite(key, value: id)
        return id
    }

    // MARK: - Token Handling

    func handleDeviceToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        let lastTokenKey = "apns.lastRegisteredToken"
        guard UserDefaults.standard.string(forKey: lastTokenKey) != token else { return }

        #if DEBUG
        print("[APNS] Registering new device token with backend")
        #endif
        if await registerWithBackend(token: token) {
            UserDefaults.standard.set(token, forKey: lastTokenKey)
        }
    }

    // MARK: - Private

    private struct RegisterBody: Encodable {
        let subscriberId: String
        let deviceToken: String
        let platform = "ios"
    }

    @discardableResult
    private func registerWithBackend(token: String) async -> Bool {
        guard let url = URL(string: relayURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.httpBody = try? JSONEncoder().encode(
            RegisterBody(subscriberId: subscriberId, deviceToken: token)
        )

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            #if DEBUG
            print("[APNS] Token registration HTTP \(status)")
            #endif
            return (200..<300).contains(status)
        } catch {
            #if DEBUG
            print("[APNS] Token registration failed: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Keychain helpers

    private func keychainRead(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainWrite(_ key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(attributes as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

// MARK: - Live Activity Push Tokens (future)
//
// To enable server-push updates for Live Activities:
//
//   1. In LiveActivityManager, change each Activity.request(... pushType: nil)
//      to pushType: .token.
//
//   2. After starting an activity, observe Activity<Attrs>.pushTokenUpdates
//      (AsyncSequence) and POST each token to your relay with
//      { "subscriberId": ..., "activityToken": ..., "activityKind": "standard"|"critical" }.
//      Live Activity tokens are per-activity (not the same as the device token above).
//
//   3. Your relay must forward Live Activity updates to APNs with:
//        apns-push-type:  liveactivity
//        apns-topic:      de.felixschick.pegelwatch.push-type.liveactivity
//      Payload must include: aps.event, aps.content-state (matching ContentState),
//      aps.timestamp, and optionally aps.stale-date / aps.dismissal-date.
//
//   Note: Verify that your Novu APNs provider supports custom payload overrides
//   before routing Live Activity updates through Novu. A direct APNs path (e.g. HTTP/2
//   to api.push.apple.com) may be needed for this specific push type.
