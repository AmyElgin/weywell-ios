import CoreLocation
import Foundation
import MapKit
import UIKit
import UserNotifications

struct RoutePoint: Codable {
  let latitude: Double
  let longitude: Double
  var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

final class WeywellNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  static let shared = WeywellNotificationDelegate()
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }
}

struct SavedMonitor: Codable, Identifiable {
  enum Kind: String, Codable, CaseIterable {
    case area = "Area"
    case route = "Route"
  }
  let id: UUID
  var name: String
  var kind: Kind
  var radiusKilometres: Int
  var isEnabled: Bool
  var latitude: Double?
  var longitude: Double?
  var routePoints: [RoutePoint]? = nil
}

@MainActor
final class MonitorManager: ObservableObject {
  static let shared = MonitorManager()
  @Published private(set) var monitors: [SavedMonitor] = []
  @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
  private let key = "weywell.savedMonitors"
  private let notifiedKey = "weywell.notifiedNoticeIDs"
  private var notifiedIDs: Set<String> = []

  private init() {
    if let data = UserDefaults.standard.data(forKey: key),
      let saved = try? JSONDecoder().decode([SavedMonitor].self, from: data)
    {
      monitors = saved
    }
    notifiedIDs = Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? [])
    refreshPermission()
  }

  func refreshPermission() {
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        self?.notificationStatus = settings.authorizationStatus
        if settings.authorizationStatus == .authorized {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }
  }

  func requestPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      [weak self] _, _ in
      Task { @MainActor in self?.refreshPermission() }
    }
  }

  func add(
    name: String, kind: SavedMonitor.Kind, radius: Int, coordinate: CLLocationCoordinate2D? = nil
  ) {
    monitors.append(
      .init(
        id: UUID(), name: name, kind: kind, radiusKilometres: radius, isEnabled: true,
        latitude: coordinate?.latitude, longitude: coordinate?.longitude))
    persist()
  }

  func addRoute(name: String, route: MKRoute) {
    let vertices = route.polyline.points()
    let step = max(1, route.polyline.pointCount / 500)
    var points = stride(from: 0, to: route.polyline.pointCount, by: step).map {
      index -> RoutePoint in
      let coordinate = vertices[index].coordinate
      return RoutePoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    if let last = (0..<route.polyline.pointCount).last {
      let coordinate = vertices[last].coordinate
      points.append(RoutePoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
    monitors.append(
      .init(
        id: UUID(), name: name, kind: .route, radiusKilometres: 1, isEnabled: true, latitude: nil,
        longitude: nil, routePoints: points))
    persist()
  }

  func toggle(_ monitor: SavedMonitor) {
    guard let index = monitors.firstIndex(where: { $0.id == monitor.id }) else { return }
    monitors[index].isEnabled.toggle()
    persist()
  }

  func delete(at offsets: IndexSet) {
    monitors.remove(atOffsets: offsets)
    persist()
  }

  func delete(_ monitor: SavedMonitor) {
    monitors.removeAll { $0.id == monitor.id }
    persist()
  }

  func deleteAll(sync: Bool = true) {
    monitors.removeAll()
    persist(sync: sync)
  }

  func matchingMonitorNames(for update: SafetyUpdate) -> [String] {
    monitors.filter { $0.isEnabled && $0.matches(update) }.map(\.name)
  }

  func sendTestAlert() {
    let content = UNMutableNotificationContent()
    content.title = "Weywell alert"
    content.body =
      "Unsafe behaviour reported near a monitored area. Open Weywell to check the context."
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
    UNUserNotificationCenter.current().add(request)
  }

  func notifyIfNeeded(for update: SafetyUpdate) {
    guard notificationStatus == .authorized,
      !matchingMonitorNames(for: update).isEmpty,
      !notifiedIDs.contains(update.id.uuidString)
    else { return }

    notifiedIDs.insert(update.id.uuidString)
    UserDefaults.standard.set(Array(notifiedIDs), forKey: notifiedKey)

    let content = UNMutableNotificationContent()
    content.title = "Weywell alert"
    content.body = "\(update.title) near \(update.locationText)."
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "report-\(update.id.uuidString)", content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
    UNUserNotificationCenter.current().add(request)
  }

  private func persist(sync: Bool = true) {
    if let data = try? JSONEncoder().encode(monitors) {
      UserDefaults.standard.set(data, forKey: key)
    }
    if sync { Task { await PushSync.shared.sync() } }
  }
}

extension SavedMonitor {
  fileprivate func matches(_ update: SafetyUpdate) -> Bool {
    if kind == .route {
      guard let routePoints, routePoints.count > 1 else { return false }
      let coordinates = routePoints.map(\.coordinate)
      let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
      return line.distance(to: update.coordinates) <= Double(radiusKilometres) * 1_000
    }
    guard let latitude, let longitude else { return false }
    let savedLocation = CLLocation(latitude: latitude, longitude: longitude)
    let updateLocation = CLLocation(
      latitude: update.coordinates.latitude, longitude: update.coordinates.longitude)
    return savedLocation.distance(from: updateLocation) <= Double(radiusKilometres) * 1_000
  }
}
