import Foundation
import RevenueCat
import Security

/// Keeps private watch geometry on the server so approved reports can notify
/// the device even when Weywell is not running. No APNs or service-role secret
/// is included in the app.
@MainActor
final class PushSync: ObservableObject {
  static let shared = PushSync()
  @Published private(set) var status = "Push setup pending"

  private var deviceToken: String? {
    get { UserDefaults.standard.string(forKey: "weywell.apnsToken") }
    set { UserDefaults.standard.set(newValue, forKey: "weywell.apnsToken") }
  }
  private var endpoint: URL? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String else {
      return nil
    }
    return URL(string: raw)
  }
  private var apiKey: String? {
    Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String
  }
  private let keychainAccount = "weywell.pushAuthSession"

  func receivedDeviceToken(_ token: Data) {
    deviceToken = token.map { String(format: "%02x", $0) }.joined()
    Task { await sync() }
  }

  func registrationFailed(_ error: Error) {
    status = "Push registration unavailable on this device"
    NSLog("Weywell APNs registration: %@", error.localizedDescription)
  }

  func sync() async {
    guard let endpoint, let apiKey, let deviceToken else {
      status = "Waiting for device push registration"
      return
    }
    do {
      let auth = try await validSession(endpoint: endpoint, apiKey: apiKey)
      let base = endpoint.appending(path: "rest/v1")
      let user = auth.user.id.uuidString.lowercased()
      let device: [String: Any] = [
        "user_id": user,
        "token": deviceToken,
        "environment": Self.environment,
        "revenue_cat_user_id": Purchases.shared.appUserID,
      ]
      try await sendJSON(
        device, to: base.appending(path: "push_devices"), method: "POST", bearer: auth.accessToken,
        apiKey: apiKey, prefer: "resolution=merge-duplicates")

      // Upsert before removing obsolete watches. Deleting every row on
      // refresh would erase push_deliveries and resend old notices.
      let watches = PurchaseManager.shared.isPro ? MonitorManager.shared.monitors : []
      let rows: [[String: Any]] = watches.compactMap { watch in
        var row: [String: Any] = [
          "id": watch.id.uuidString.lowercased(), "user_id": user,
          "name": String(watch.name.prefix(80)), "kind": watch.kind == .area ? "area" : "route",
          "radius_km": watch.radiusKilometres, "enabled": watch.isEnabled,
        ]
        if watch.kind == .area {
          guard let lat = watch.latitude, let lon = watch.longitude else { return nil }
          row["latitude"] = lat
          row["longitude"] = lon
        } else {
          guard let points = watch.routePoints, points.count > 1 else { return nil }
          row["route_points"] = points.prefix(501).map {
            ["latitude": $0.latitude, "longitude": $0.longitude]
          }
        }
        return row
      }
      if !rows.isEmpty {
        try await sendJSON(
          rows, to: base.appending(path: "push_watches"), method: "POST", bearer: auth.accessToken,
          apiKey: apiKey, prefer: "resolution=merge-duplicates")
      }
      var deleteURL = URLComponents(
        url: base.appending(path: "push_watches"), resolvingAgainstBaseURL: false)!
      var filters = [URLQueryItem(name: "user_id", value: "eq.\(user)")]
      if !rows.isEmpty {
        let ids = watches.map { $0.id.uuidString.lowercased() }.joined(separator: ",")
        filters.append(.init(name: "id", value: "not.in.(\(ids))"))
      }
      deleteURL.queryItems = filters
      try await sendJSON(
        nil, to: deleteURL.url!, method: "DELETE", bearer: auth.accessToken, apiKey: apiKey)
      status = "Your watches are synced"
    } catch {
      status = "Background alerts not connected yet"
      NSLog("Weywell push sync: %@", error.localizedDescription)
    }
  }

  func deleteServerData() async {
    guard let endpoint, let apiKey,
      let auth = try? await validSession(endpoint: endpoint, apiKey: apiKey)
    else { return }
    let base = endpoint.appending(path: "rest/v1")
    let user = auth.user.id.uuidString.lowercased()
    for table in ["push_watches", "push_devices"] {
      var components = URLComponents(
        url: base.appending(path: table), resolvingAgainstBaseURL: false)!
      components.queryItems = [.init(name: "user_id", value: "eq.\(user)")]
      try? await sendJSON(
        nil, to: components.url!, method: "DELETE", bearer: auth.accessToken, apiKey: apiKey)
    }
  }

  func uploadReportPhoto(_ data: Data, reportID: UUID) async throws -> String {
    guard let endpoint, let apiKey else { throw PushError.notConfigured }
    let auth = try await validSession(endpoint: endpoint, apiKey: apiKey)
    let user = auth.user.id.uuidString.lowercased()
    let path = "\(user)/\(reportID.uuidString.lowercased()).jpg"
    var request = URLRequest(
      url: URL(string: "storage/v1/object/community-report-photos/\(path)", relativeTo: endpoint)!
        .absoluteURL)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    request.setValue("false", forHTTPHeaderField: "x-upsert")
    request.httpBody = data
    let (_, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else {
      throw PushError.requestFailed
    }
    return path
  }

  func authenticatedAccessToken() async throws -> String {
    guard let endpoint, let apiKey else { throw PushError.notConfigured }
    return try await validSession(endpoint: endpoint, apiKey: apiKey).accessToken
  }

  func deleteReportPhoto(_ path: String) async {
    guard let endpoint, let apiKey,
      let auth = try? await validSession(endpoint: endpoint, apiKey: apiKey)
    else { return }
    let safePath = path.split(separator: "/").map(String.init).joined(separator: "/")
    let url = URL(
      string: "storage/v1/object/community-report-photos/\(safePath)", relativeTo: endpoint)!
      .absoluteURL
    var request = URLRequest(url: url)
    request.httpMethod = "DELETE"
    request.setValue(apiKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    _ = try? await URLSession.shared.data(for: request)
  }

  func signedPhotoURL(for path: String) async -> URL? {
    guard let endpoint, let apiKey,
      let auth = try? await validSession(endpoint: endpoint, apiKey: apiKey)
    else { return nil }
    let encodedPath = path.split(separator: "/").map {
      String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
    }.joined(separator: "/")
    let url = URL(
      string: "storage/v1/object/sign/community-report-photos/\(encodedPath)", relativeTo: endpoint)!
      .absoluteURL
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["expiresIn": 1800])
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
      let result = try? JSONDecoder().decode(SignedObject.self, from: data)
    else { return nil }
    return URL(string: result.signedURL, relativeTo: endpoint.appending(path: "storage/v1"))?
      .absoluteURL
  }

  private func validSession(endpoint: URL, apiKey: String) async throws -> AuthSession {
    if let stored = Keychain.read(keychainAccount),
      let session = try? JSONDecoder().decode(AuthSession.self, from: stored)
    {
      if session.expiresAt > Date().timeIntervalSince1970 + 60 { return session }
      do {
        let renewed = try await authRequest(
          endpoint: endpoint, apiKey: apiKey, path: "token?grant_type=refresh_token",
          body: ["refresh_token": session.refreshToken])
        Keychain.save(try JSONEncoder().encode(renewed), keychainAccount)
        return renewed
      } catch {
        // Do not create a new anonymous account for a temporary
        // network error: that would orphan the old watches.
        throw error
      }
    }
    let session = try await authRequest(
      endpoint: endpoint, apiKey: apiKey, path: "signup", body: ["data": [:]])
    Keychain.save(try JSONEncoder().encode(session), keychainAccount)
    return session
  }

  private func authRequest(endpoint: URL, apiKey: String, path: String, body: [String: Any])
    async throws -> AuthSession
  {
    var request = URLRequest(url: URL(string: "auth/v1/\(path)", relativeTo: endpoint)!.absoluteURL)
    request.httpMethod = "POST"
    request.setValue(apiKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else {
      throw PushError.requestFailed
    }
    return try JSONDecoder().decode(AuthSession.self, from: data)
  }

  private func sendJSON(
    _ value: Any?, to url: URL, method: String, bearer: String, apiKey: String,
    prefer: String? = nil
  ) async throws {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue(apiKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
    if let value { request.httpBody = try JSONSerialization.data(withJSONObject: value) }
    let (_, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else {
      throw PushError.requestFailed
    }
  }

  private static var environment: String {
    #if DEBUG
      return "sandbox"
    #else
      return "production"
    #endif
  }
}

private enum PushError: Error { case requestFailed, notConfigured }
private struct SignedObject: Decodable {
  let signedURL: String
  enum CodingKeys: String, CodingKey { case signedURL = "signedURL" }
}

private struct AuthSession: Codable {
  let accessToken: String
  let refreshToken: String
  let expiresAt: Double
  let user: AuthUser
  enum CodingKeys: String, CodingKey {
    case user
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresAt = "expires_at"
    case expiresIn = "expires_in"
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    accessToken = try values.decode(String.self, forKey: .accessToken)
    refreshToken = try values.decode(String.self, forKey: .refreshToken)
    user = try values.decode(AuthUser.self, forKey: .user)
    expiresAt =
      try values.decodeIfPresent(Double.self, forKey: .expiresAt)
      ?? Date().timeIntervalSince1970
      + (try values.decodeIfPresent(Double.self, forKey: .expiresIn) ?? 3600)
  }
  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(accessToken, forKey: .accessToken)
    try values.encode(refreshToken, forKey: .refreshToken)
    try values.encode(expiresAt, forKey: .expiresAt)
    try values.encode(user, forKey: .user)
  }
}

private struct AuthUser: Codable { let id: UUID }

private enum Keychain {
  static func read(_ account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }
  static func save(_ data: Data, _ account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
    var item = query
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(item as CFDictionary, nil)
  }
}
