import CoreLocation
import Foundation

/// A lightweight Supabase Data API client. It intentionally uses only the public,
/// publishable key which is safe to ship when Row Level Security is enabled.
@MainActor
final class BackendService: ObservableObject {
  static let shared = BackendService()

  enum State: Equatable {
    case offline, syncing, connected
    case failed(String)
  }
  @Published private(set) var state: State = .offline
  @Published private(set) var moderatorUserID: UUID?
  @Published private(set) var moderatorError: String?
  private var moderatorAccessToken: String?
  private var moderatorRefreshToken: String?
  private var moderatorTokenExpiresAt = Date.distantPast

  private let session = URLSession.shared
  private var baseURL: URL? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
      value.hasPrefix("https://"), !value.contains("YOUR_")
    else { return nil }
    return URL(string: value)
  }
  private var publishableKey: String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
      !value.isEmpty, !value.contains("YOUR_")
    else { return nil }
    return value
  }

  var isConfigured: Bool { baseURL != nil && publishableKey != nil }

  func fetchActiveNotices() async -> [SafetyUpdate] {
    guard let baseURL, let publishableKey else { return [] }
    state = .syncing
    var components = URLComponents(
      url: baseURL.appending(path: "rest/v1/safety_notices"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      .init(
        name: "select",
        value:
          "id,category,title,location_text,latitude,longitude,detail,reported_at,expires_at,photo_path"
      ),
      .init(name: "status", value: "eq.approved"),
      .init(name: "expires_at", value: "gt.\(ISO8601DateFormatter().string(from: Date()))"),
      .init(name: "order", value: "reported_at.desc"),
    ]
    var request = URLRequest(url: components.url!)
    request.setValue(publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
    do {
      let (data, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw URLError(.badServerResponse)
      }
      let formatter = JSONDecoder()
      formatter.dateDecodingStrategy = .iso8601
      let notices = try formatter.decode([RemoteNotice].self, from: data).map {
        SafetyUpdate(remote: $0)
      }
      state = .connected
      return notices
    } catch {
      state = .failed("Couldn’t refresh shared notices")
      return []
    }
  }

  func submit(_ update: SafetyUpdate, photoData: Data? = nil) async -> Bool {
    guard let baseURL, let publishableKey else { return false }
    state = .syncing
    var photoPath: String?
    if let photoData {
      do {
        photoPath = try await PushSync.shared.uploadReportPhoto(photoData, reportID: update.id)
      } catch {
        state = .failed("Couldn’t upload the photo. Try again or send the alert without it.")
        return false
      }
    }
    let userAccessToken: String
    do { userAccessToken = try await PushSync.shared.authenticatedAccessToken() } catch {
      if let photoPath { await PushSync.shared.deleteReportPhoto(photoPath) }
      state = .failed("Couldn’t connect your report to the community right now.")
      return false
    }
    var request = URLRequest(url: baseURL.appending(path: "rest/v1/safety_notices"))
    request.httpMethod = "POST"
    request.setValue(publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(userAccessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
    request.httpBody = try? JSONEncoder().encode(
      ReportPayload(update: update, photoPath: photoPath))
    do {
      let (_, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true
      else { throw URLError(.badServerResponse) }
      state = .connected
      return true
    } catch {
      if let photoPath { await PushSync.shared.deleteReportPhoto(photoPath) }
      state = .failed("Couldn’t submit the report. Please try again.")
      return false
    }
  }

  func signedPhotoURL(for path: String) async -> URL? {
    await PushSync.shared.signedPhotoURL(for: path)
  }

  var isModeratorSignedIn: Bool { moderatorUserID != nil && moderatorAccessToken != nil }

  func moderatorSignIn(email: String, password: String) async -> Bool {
    guard let baseURL, let publishableKey else {
      moderatorError = "Weywell’s backend isn’t configured."
      return false
    }
    moderatorError = nil
    do {
      var request = URLRequest(
        url: URL(string: "auth/v1/token?grant_type=password", relativeTo: baseURL)!)
      request.httpMethod = "POST"
      request.setValue(publishableKey, forHTTPHeaderField: "apikey")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password,
      ])
      let (data, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        moderatorError = "Sign-in failed. Check the email and password."
        return false
      }
      let session = try JSONDecoder().decode(ModeratorAuthSession.self, from: data)
      let user = session.user.id.uuidString.lowercased()
      var check = URLComponents(
        url: baseURL.appending(path: "rest/v1/moderators"), resolvingAgainstBaseURL: false)!
      check.queryItems = [
        .init(name: "select", value: "user_id"), .init(name: "user_id", value: "eq.\(user)"),
      ]
      var checkRequest = URLRequest(url: check.url!)
      checkRequest.setValue(publishableKey, forHTTPHeaderField: "apikey")
      checkRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
      let (checkData, checkResponse) = try await self.session.data(for: checkRequest)
      guard (checkResponse as? HTTPURLResponse)?.statusCode == 200,
        let moderators = try? JSONDecoder().decode([ModeratorID].self, from: checkData),
        moderators.contains(where: { $0.userID == session.user.id })
      else {
        moderatorError =
          "This account isn’t on Weywell’s moderator list. Ask the project owner to grant moderator access."
        return false
      }
      moderatorAccessToken = session.accessToken
      moderatorRefreshToken = session.refreshToken
      moderatorTokenExpiresAt = Date().addingTimeInterval(session.expiresIn)
      moderatorUserID = session.user.id
      return true
    } catch {
      moderatorError = "Couldn’t reach the sign-in service. Check your connection and try again."
      return false
    }
  }

  func sendModeratorPasswordRecovery(email: String) async throws {
    guard let baseURL, let publishableKey else { throw ModeratorError.requestFailed }
    var components = URLComponents(
      url: baseURL.appending(path: "auth/v1/recover"), resolvingAgainstBaseURL: false)!
    #if DEBUG
      let redirectURL = "http://localhost:3000"
    #else
      let redirectURL = "weywell://auth/callback"
    #endif
    components.queryItems = [.init(name: "redirect_to", value: redirectURL)]
    var request = URLRequest(url: components.url!)
    request.httpMethod = "POST"
    request.setValue(publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "email": email.trimmingCharacters(in: .whitespacesAndNewlines)
    ])
    let (_, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else {
      throw ModeratorError.requestFailed
    }
  }

  func setRecoveredPassword(accessToken: String, newPassword: String) async throws {
    guard let baseURL, let publishableKey else { throw ModeratorError.requestFailed }
    var request = URLRequest(url: URL(string: "auth/v1/user", relativeTo: baseURL)!)
    request.httpMethod = "PUT"
    request.setValue(publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["password": newPassword])
    let (_, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else {
      throw ModeratorError.requestFailed
    }
  }

  func moderatorSignOut() {
    moderatorAccessToken = nil
    moderatorRefreshToken = nil
    moderatorTokenExpiresAt = .distantPast
    moderatorUserID = nil
    moderatorError = nil
  }

  func fetchPendingReports() async throws -> [ModerationReport] {
    let (baseURL, publishableKey, token) = try await moderatorCredentials()
    var components = URLComponents(
      url: baseURL.appending(path: "rest/v1/safety_notices"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      .init(
        name: "select",
        value:
          "id,category,title,location_text,latitude,longitude,detail,reported_at,expires_at,photo_path"
      ),
      .init(name: "status", value: "eq.pending"),
      .init(name: "expires_at", value: "gt.\(ISO8601DateFormatter().string(from: Date()))"),
      .init(name: "order", value: "reported_at.asc"),
    ]
    var request = URLRequest(url: components.url!)
    request.setValue(publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw ModeratorError.requestFailed
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode([ModerationReport].self, from: data)
  }

  func reviewReport(_ report: ModerationReport, approve: Bool) async throws {
    let (baseURL, publishableKey, token) = try await moderatorCredentials()
    var components = URLComponents(
      url: baseURL.appending(path: "rest/v1/safety_notices"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      .init(name: "id", value: "eq.\(report.id.uuidString.lowercased())"),
      .init(name: "status", value: "eq.pending"),
    ]
    var request = URLRequest(url: components.url!)
    request.httpMethod = "PATCH"
    request.setValue(publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("return=representation", forHTTPHeaderField: "Prefer")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "status": approve ? "approved" : "rejected"
    ])
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw ModeratorError.requestFailed
    }
    guard let changed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
      !changed.isEmpty
    else { throw ModeratorError.alreadyReviewed }
  }

  func moderatorPhotoURL(for path: String) async -> URL? {
    guard let (baseURL, publishableKey, moderatorAccessToken) = try? await moderatorCredentials()
    else { return nil }
    let encoded = path.split(separator: "/").map {
      String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
    }.joined(separator: "/")
    let url = URL(
      string: "storage/v1/object/sign/community-report-photos/\(encoded)", relativeTo: baseURL)!
      .absoluteURL
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(moderatorAccessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["expiresIn": 900])
    guard let (data, response) = try? await session.data(for: request),
      (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true,
      let signed = try? JSONDecoder().decode(SignedPhotoURL.self, from: data)
    else { return nil }
    return URL(string: signed.signedURL, relativeTo: baseURL.appending(path: "storage/v1"))?
      .absoluteURL
  }

  private func moderatorCredentials() async throws -> (URL, String, String) {
    guard let baseURL, let publishableKey, let moderatorAccessToken,
      let moderatorRefreshToken, let moderatorUserID
    else { throw ModeratorError.notSignedIn }
    if moderatorTokenExpiresAt > Date().addingTimeInterval(60) {
      return (baseURL, publishableKey, moderatorAccessToken)
    }
    do {
      var request = URLRequest(
        url: URL(string: "auth/v1/token?grant_type=refresh_token", relativeTo: baseURL)!)
      request.httpMethod = "POST"
      request.setValue(publishableKey, forHTTPHeaderField: "apikey")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "refresh_token": moderatorRefreshToken
      ])
      let (data, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw ModeratorError.requestFailed
      }
      let renewed = try JSONDecoder().decode(ModeratorAuthSession.self, from: data)
      guard renewed.user.id == moderatorUserID else { throw ModeratorError.notSignedIn }
      self.moderatorAccessToken = renewed.accessToken
      self.moderatorRefreshToken = renewed.refreshToken
      self.moderatorTokenExpiresAt = Date().addingTimeInterval(renewed.expiresIn)
      return (baseURL, publishableKey, renewed.accessToken)
    } catch {
      moderatorSignOut()
      throw ModeratorError.notSignedIn
    }
  }
}

struct ModerationReport: Decodable, Identifiable {
  let id: UUID
  let category: String
  let title: String
  let locationText: String
  let latitude: Double
  let longitude: Double
  let detail: String
  let reportedAt: Date
  let expiresAt: Date
  let photoPath: String?

  enum CodingKeys: String, CodingKey {
    case id, category, title, latitude, longitude, detail
    case locationText = "location_text"
    case reportedAt = "reported_at"
    case expiresAt = "expires_at"
    case photoPath = "photo_path"
  }
}

private struct ModeratorAuthSession: Decodable {
  let accessToken: String
  let refreshToken: String
  let expiresIn: Double
  let user: ModeratorAuthUser
  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case user
  }
}
private struct ModeratorAuthUser: Decodable { let id: UUID }
private struct ModeratorID: Decodable {
  let userID: UUID
  enum CodingKeys: String, CodingKey { case userID = "user_id" }
}
private struct SignedPhotoURL: Decodable {
  let signedURL: String
  enum CodingKeys: String, CodingKey { case signedURL = "signedURL" }
}
private enum ModeratorError: Error { case notSignedIn, requestFailed, alreadyReviewed }

private struct RemoteNotice: Decodable {
  let id: UUID
  let category: String
  let title: String
  let locationText: String
  let latitude: Double
  let longitude: Double
  let detail: String
  let reportedAt: Date
  let expiresAt: Date
  let photoPath: String?

  enum CodingKeys: String, CodingKey {
    case id, category, title, latitude, longitude, detail
    case locationText = "location_text"
    case reportedAt = "reported_at"
    case expiresAt = "expires_at"
    case photoPath = "photo_path"
  }
}

private struct ReportPayload: Encodable {
  let category: String
  let title: String
  let locationText: String
  let latitude: Double
  let longitude: Double
  let detail: String
  let status = "pending"
  let photoPath: String?

  enum CodingKeys: String, CodingKey {
    case category, title, latitude, longitude, detail, status
    case locationText = "location_text"
    case photoPath = "photo_path"
  }

  init(update: SafetyUpdate, photoPath: String?) {
    category = update.category.databaseValue
    title = update.title
    locationText = update.locationText
    latitude = update.coordinates.latitude
    longitude = update.coordinates.longitude
    detail = update.detail
    self.photoPath = photoPath
  }
}

extension SafetyCategory {
  fileprivate var databaseValue: String {
    switch self {
    case .routeDisruption: "route_disruption"
    case .unsafeBehaviour: "unsafe_behaviour"
    case .crimeReported: "crime_reported"
    case .neighbourhood: "neighbourhood"
    }
  }

  fileprivate init?(databaseValue: String) {
    switch databaseValue {
    case "route_disruption": self = .routeDisruption
    case "unsafe_behaviour": self = .unsafeBehaviour
    case "crime_reported": self = .crimeReported
    case "neighbourhood": self = .neighbourhood
    default: return nil
    }
  }
}

extension SafetyUpdate {
  fileprivate init(remote: RemoteNotice) {
    self.init(
      id: remote.id, category: SafetyCategory(databaseValue: remote.category) ?? .unsafeBehaviour,
      title: remote.title, locationText: remote.locationText, timestamp: "Shared recently",
      coordinates: .init(latitude: remote.latitude, longitude: remote.longitude),
      detail: remote.detail, expiresAt: remote.expiresAt, photoPath: remote.photoPath)
  }
}
