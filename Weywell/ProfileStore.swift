import CoreLocation
import Foundation
import MapKit

struct WeywellProfile: Codable {
  var name: String
  var address: String
  var latitude: Double
  var longitude: Double

  var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct AddressCandidate: Identifiable {
  let id = UUID()
  let title: String
  let subtitle: String
  let coordinate: CLLocationCoordinate2D
}

@MainActor
final class ProfileStore: ObservableObject {
  static let shared = ProfileStore()

  @Published private(set) var profile: WeywellProfile?
  @Published private(set) var isResolving = false
  @Published private(set) var addressMatches: [AddressCandidate] = []
  @Published var message: String?

  private let key = "weywell.profile"

  private init() {
    guard let data = UserDefaults.standard.data(forKey: key) else { return }
    profile = try? JSONDecoder().decode(WeywellProfile.self, from: data)
  }

  func search(address: String) async {
    let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedAddress.isEmpty else {
      addressMatches = []
      message = "Enter a street address, suburb and city."
      return
    }
    isResolving = true
    defer { isResolving = false }
    do {
      let matches = try await lookupAddress(trimmedAddress)
      addressMatches = matches
      message =
        matches.isEmpty
        ? "No South African address found. Try a street number, street, suburb and city."
        : "Choose the address that matches your home."
    } catch {
      addressMatches = []
      message = "Address search is unavailable right now. Check your connection and try again."
    }
  }

  func save(name: String, candidate: AddressCandidate) {
    let saved = WeywellProfile(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      address: [candidate.title, candidate.subtitle].filter { !$0.isEmpty }.joined(separator: ", "),
      latitude: candidate.coordinate.latitude, longitude: candidate.coordinate.longitude)
    profile = saved
    if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: key) }
    addressMatches = []
    message = "Home address saved and shown on the map."
  }

  func clearMatches() {
    addressMatches = []
    message = nil
  }

  func deleteProfile() {
    profile = nil
    addressMatches = []
    message = nil
    UserDefaults.standard.removeObject(forKey: key)
  }

  func saveMapArea(name: String, coordinate: CLLocationCoordinate2D) {
    let saved = WeywellProfile(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines), address: "Map area selected",
      latitude: coordinate.latitude, longitude: coordinate.longitude)
    profile = saved
    if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: key) }
    message = "Map area saved. Add a full address whenever you want to refine it."
  }

  func lookupAddress(_ address: String) async throws -> [AddressCandidate] {
    try await lookup(address, resultTypes: .address)
  }

  func lookupDestination(_ destination: String) async throws -> [AddressCandidate] {
    // A broad geocoder result (e.g. just "Durban" for "Durban City Hall")
    // must not silently become the user's chosen destination.
    let addresses = (try? await lookup(destination, resultTypes: .address)) ?? []
    let preciseAddresses = addresses.filter { Self.matchesDestination($0, query: destination) }
    if !preciseAddresses.isEmpty { return preciseAddresses }

    // Journeys may end at a landmark or public venue, not only a street address.
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = destination
    request.resultTypes = .pointOfInterest
    request.region = .init(
      center: .init(latitude: -29.8587, longitude: 31.0218), latitudinalMeters: 3_000_000,
      longitudinalMeters: 3_000_000)
    let response = try await MKLocalSearch(request: request).start()
    return Array(
      response.mapItems.compactMap { item -> AddressCandidate? in
        let place = item.placemark
        guard isSouthAfrican(place.coordinate), place.countryCode == "ZA" else { return nil }
        let candidate = AddressCandidate(
          title: item.name ?? place.name ?? destination,
          subtitle: [place.locality, place.administrativeArea, place.country]
            .compactMap { $0 }.joined(separator: ", "), coordinate: place.coordinate)
        return Self.matchesDestination(candidate, query: destination) ? candidate : nil
      }.prefix(6))
  }

  private static func matchesDestination(_ candidate: AddressCandidate, query: String) -> Bool {
    let ignored: Set<String> = ["the", "of", "and", "south", "africa"]
    func words(_ text: String) -> Set<String> {
      Set(
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
          .map(String.init).filter { !ignored.contains($0) })
    }
    let searched = words(query)
    guard !searched.isEmpty else { return false }
    let found = words(candidate.title + " " + candidate.subtitle)
    let minimumMatches = searched.count <= 2 ? searched.count : searched.count - 1
    return searched.intersection(found).count >= minimumMatches
  }

  private func lookup(
    _ address: String, resultTypes: MKLocalSearch.Request.ResultType
  ) async throws -> [AddressCandidate] {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery =
      address.localizedCaseInsensitiveContains("south africa")
      ? address : "\(address), South Africa"
    request.region = .init(
      center: .init(latitude: -29.8587, longitude: 31.0218), latitudinalMeters: 3_000_000,
      longitudinalMeters: 3_000_000)
    request.resultTypes = resultTypes
    if let response = try? await MKLocalSearch(request: request).start() {
      let matches = response.mapItems.compactMap { item -> AddressCandidate? in
        let place = item.placemark
        guard isSouthAfrican(place.coordinate), place.countryCode == "ZA" else { return nil }
        return AddressCandidate(
          title: place.name ?? item.name ?? address,
          subtitle: [place.locality, place.administrativeArea, place.country].compactMap { $0 }
            .joined(separator: ", "), coordinate: place.coordinate)
      }
      if !matches.isEmpty { return Array(matches.prefix(6)) }
    }
    let geocoded = try await CLGeocoder().geocodeAddressString(
      address.localizedCaseInsensitiveContains("south africa")
        ? address : "\(address), South Africa")
    return Array(
      geocoded.compactMap { place -> AddressCandidate? in
        guard let coordinate = place.location?.coordinate, isSouthAfrican(coordinate),
          place.isoCountryCode == "ZA"
        else { return nil }
        return AddressCandidate(
          title: [place.subThoroughfare, place.thoroughfare].compactMap { $0 }.joined(
            separator: " "
          ).isEmpty
            ? (place.name ?? address)
            : [place.subThoroughfare, place.thoroughfare].compactMap { $0 }.joined(separator: " "),
          subtitle: [place.subLocality, place.locality, place.administrativeArea, place.country]
            .compactMap { $0 }.joined(separator: ", "), coordinate: coordinate)
      }.prefix(6))
  }

  private func isSouthAfrican(_ coordinate: CLLocationCoordinate2D) -> Bool {
    (-35...(-22)).contains(coordinate.latitude) && (16...33).contains(coordinate.longitude)
  }
}
