import CoreLocation
import MapKit

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  @Published var region = MKCoordinateRegion(
    center: .init(latitude: -30.5595, longitude: 22.9375),
    span: .init(latitudeDelta: 12, longitudeDelta: 12))
  @Published var authorization: CLAuthorizationStatus = .notDetermined
  @Published private(set) var currentLocation: CLLocation?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func requestLocation() {
    if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    manager.startUpdatingLocation()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorization = manager.authorizationStatus
    if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
      manager.startUpdatingLocation()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    currentLocation = location
    region = .init(
      center: location.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
    manager.stopUpdatingLocation()
  }
}
