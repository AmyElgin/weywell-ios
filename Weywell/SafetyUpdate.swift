import CoreLocation
import Foundation

enum SafetyCategory: String, CaseIterable, Identifiable, Codable {
  case routeDisruption = "Road closure / protest"
  case unsafeBehaviour = "Unsafe behaviour"
  case crimeReported = "Crime reported"
  case neighbourhood = "Recent break-ins"

  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .routeDisruption: "exclamationmark.triangle.fill"
    case .unsafeBehaviour: "eye.fill"
    case .crimeReported: "shield.fill"
    case .neighbourhood: "house.fill"
    }
  }
}

struct SafetyUpdate: Identifiable {
  let id: UUID
  let category: SafetyCategory
  let title: String
  let locationText: String
  let timestamp: String
  let coordinates: CLLocationCoordinate2D
  let detail: String
  let expiresAt: Date
  let photoPath: String?

  init(
    id: UUID = UUID(), category: SafetyCategory, title: String, locationText: String,
    timestamp: String, coordinates: CLLocationCoordinate2D, detail: String, expiresAt: Date,
    photoPath: String? = nil
  ) {
    self.id = id
    self.category = category
    self.title = title
    self.locationText = locationText
    self.timestamp = timestamp
    self.coordinates = coordinates
    self.detail = detail
    self.expiresAt = expiresAt
    self.photoPath = photoPath
  }

  var isActive: Bool { expiresAt > Date() }
  var expiryText: String {
    let seconds = Int(expiresAt.timeIntervalSinceNow)
    guard seconds > 0 else { return "Expired" }
    if seconds < 3_600 { return "Expires in \(max(1, seconds / 60)) min" }
    return "Expires in \(max(1, seconds / 3_600)) hr"
  }
}

@MainActor
final class NoticeStore: ObservableObject {
  @Published private(set) var updates: [SafetyUpdate] = []

  var activeUpdates: [SafetyUpdate] { updates.filter(\.isActive) }

  func mergeShared(_ shared: [SafetyUpdate]) {
    let merged = (updates + shared).reduce(into: [UUID: SafetyUpdate]()) { $0[$1.id] = $1 }
    updates = merged.values.sorted { $0.expiresAt < $1.expiresAt }
  }

  func makePending(
    category: SafetyCategory, locationText: String, coordinates: CLLocationCoordinate2D
  ) -> SafetyUpdate {
    let title = category == .neighbourhood ? "Recent break-ins in this area" : category.rawValue
    let update = SafetyUpdate(
      category: category, title: title, locationText: locationText, timestamp: "Just now",
      coordinates: coordinates,
      detail: "A new community update is waiting for moderation. Its location is kept approximate.",
      expiresAt: Date().addingTimeInterval(category == .neighbourhood ? 7 * 86_400 : 24 * 3_600))
    return update
  }
}
