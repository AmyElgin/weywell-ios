import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var location = LocationManager()
  @State private var position: MapCameraPosition = .region(
    .init(
      center: .init(latitude: -30.5595, longitude: 22.9375),
      span: .init(latitudeDelta: 12, longitudeDelta: 12)))
  @State private var center = CLLocationCoordinate2D(latitude: -30.5595, longitude: 22.9375)
  @State private var span = 12.0
  @State private var radius = 20.0
  @State private var category: SafetyCategory?
  @State private var selected: SafetyUpdate?
  @State private var filters = true
  @State private var route = false
  @State private var report = false
  @State private var alerts = false
  @State private var profileSheet = false
  @State private var plus = false
  @State private var clock = Date()
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var notices: NoticeStore
  @EnvironmentObject private var profile: ProfileStore
  @EnvironmentObject private var monitoring: MonitorManager

  private var updates: [SafetyUpdate] {
    _ = clock
    let area = profile.profile?.coordinate ?? center
    let origin = CLLocation(latitude: area.latitude, longitude: area.longitude)
    return notices.activeUpdates.filter { update in
      (category == nil || update.category == category)
        && origin.distance(
          from: CLLocation(
            latitude: update.coordinates.latitude, longitude: update.coordinates.longitude))
          <= radius * 1_000
    }
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.weywellSky.ignoresSafeArea()
      VStack(spacing: 0) {
        header
        map
        controls
      }
      HStack {
        Nav(icon: "map.fill", text: "Map", active: true) {}
        Nav(icon: "bell.fill", text: "Alerts", active: false) { alerts = true }
        Nav(icon: "person.crop.circle", text: "Profile", active: false) { profileSheet = true }
      }
      .padding(.horizontal, 30).padding(.top, 10).padding(.bottom, 24)
      .background {
        UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25).fill(.white)
          .ignoresSafeArea(edges: .bottom)
      }
    }
    .sheet(item: $selected) { Detail(update: $0) { route = true } }
    .sheet(isPresented: $route) {
      RouteChecker(
        origin: profile.profile?.coordinate ?? center,
        originName: profile.profile == nil ? "Map centre" : "Saved home")
    }
    .sheet(isPresented: $report) { ReportSheet(center: center, location: location) }
    .sheet(isPresented: $alerts) { AlertCentre() }
    .sheet(isPresented: $profileSheet) { ProfileView(mapCenter: center) }
    .sheet(isPresented: $plus) { PlusView() }
    .onAppear {
      location.requestLocation()
      focusSavedArea()
    }
    .task { await refreshNotices() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshNotices() } }
    }
    .onChange(of: purchases.isPro) { _, active in
      if active { Task { await refreshNotices() } } else { category = nil }
    }
    .onChange(of: location.region.center.latitude) { _, _ in
      if profile.profile == nil { setMap(location.region.center, 0.24) }
    }
    .onChange(of: profile.profile?.latitude) { _, _ in focusSavedArea() }
    .onChange(of: profile.profile?.longitude) { _, _ in focusSavedArea() }
    .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { clock = $0 }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Circle().fill(Color.coral).frame(width: 7, height: 7)
          Circle().fill(Color.amber).frame(width: 7, height: 7)
          Circle().fill(Color.weywellMint).frame(width: 7, height: 7)
          Text("LOOKING OUT FOR EACH OTHER").font(
            .system(size: 9, weight: .heavy, design: .rounded)
          ).tracking(0.9).padding(.leading, 2)
        }.foregroundStyle(Color.weywellInk.opacity(0.65))
        Text("WEYWELL").font(.system(size: 30, weight: .black, design: .rounded)).tracking(-1)
          .foregroundStyle(Color.weywellInk)
        Text(
          profile.profile == nil
            ? "Local knowledge for every journey" : "Your corner of South Africa"
        )
        .font(.caption.weight(.medium)).foregroundStyle(Color.weywellInk.opacity(0.65))
      }
      Spacer(minLength: 3)
      Button {
        alerts = true
      } label: {
        Image(systemName: "bell.badge").frame(width: 42, height: 42).background(
          .white, in: Circle())
      }.accessibilityLabel("Open alerts")
      Button {
        plus = true
      } label: {
        Text(purchases.isPro ? "PLUS ✓" : "PLUS").font(.caption.bold()).tracking(0.5).padding(
          .horizontal, 11
        ).frame(height: 40).background(.white, in: Capsule())
      }.accessibilityLabel("Weywell Plus")
    }.font(.title3).padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
  }

  private var map: some View {
    Map(position: $position) {
      UserAnnotation()
      MapCircle(center: profile.profile?.coordinate ?? center, radius: radius * 1_000)
        .foregroundStyle(.blue.opacity(0.10)).stroke(.blue.opacity(0.45), lineWidth: 2)
      if let home = profile.profile {
        Annotation("Home", coordinate: home.coordinate, anchor: .bottom) {
          Image(systemName: "house.fill").font(.caption.bold()).foregroundStyle(.white).padding(11)
            .background(Color.blue, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(radius: 4)
        }
      }
      ForEach(updates) { update in
        Annotation(update.title, coordinate: update.coordinates, anchor: .bottom) {
          Button {
            selected = update
          } label: {
            Pin(category: update.category)
          }.buttonStyle(.plain)
        }
      }
    }
    .mapStyle(.standard(elevation: .flat, emphasis: .muted)).onMapCameraChange(frequency: .onEnd) {
      context in
      center = context.region.center
      span = context.region.span.latitudeDelta
    }.clipShape(RoundedRectangle(cornerRadius: 26))
    .overlay(alignment: .topLeading) {
      VStack(spacing: 8) {
        mapButton("plus", label: "Zoom in") { zoom(by: 0.55) }
        mapButton("minus", label: "Zoom out") { zoom(by: 1.8) }
        mapButton("location.fill", label: "Return to saved area") { focusSavedArea() }
      }.padding(14)
    }
    .overlay(alignment: .topTrailing) {
      Button {
        withAnimation { filters.toggle() }
      } label: {
        Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).background(
          .white, in: Circle())
      }.padding(14)
    }
    .overlay(alignment: .bottomLeading) {
      HStack(spacing: 7) {
        Circle().fill(updates.isEmpty ? Color.weywellMint : Color.coral).frame(width: 9, height: 9)
        Text(
          updates.isEmpty ? "No current alerts nearby" : "\(updates.count) community alerts nearby")
      }.font(.caption.weight(.semibold)).padding(10).background(.white.opacity(0.96), in: Capsule())
        .padding(14)
    }
    .padding(.horizontal, 14).frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var controls: some View {
    VStack(spacing: 10) {
      if filters {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("Within \(Int(radius)) km").font(.subheadline.bold())
            Spacer()
            Text(category?.shortName ?? "All alerts").font(.caption.bold()).foregroundStyle(
              category?.tint ?? .secondary)
          }
          Slider(value: $radius, in: 5...60, step: 5).tint(.blue)
          if purchases.isPro {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack {
                Filter(title: "All", active: category == nil, tint: .blue) { category = nil }
                ForEach(SafetyCategory.allCases) { item in
                  Filter(title: item.shortName, active: category == item, tint: item.tint) {
                    category = item
                  }
                }
              }
            }
          } else {
            Button {
              plus = true
            } label: {
              Label("Filter by alert type with Weywell Plus", systemImage: "lock.fill").font(
                .caption.bold()
              ).frame(maxWidth: .infinity).padding(10).background(
                Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
            }.foregroundStyle(.blue)
          }
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 19))
      }
      HStack(spacing: 10) {
        Button {
          report = true
        } label: {
          Label("Send an alert", systemImage: "megaphone.fill").font(.headline)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(Color.coral, in: RoundedRectangle(cornerRadius: 18))
        }.foregroundStyle(.white)
        Button {
          route = true
        } label: {
          Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").font(.headline)
            .frame(width: 56, height: 56).background(.white, in: RoundedRectangle(cornerRadius: 18))
        }.foregroundStyle(.blue).accessibilityLabel("Plan a journey")
      }.padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 112)
    }
  }
  private func mapButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.headline).frame(width: 44, height: 44).background(
        .white, in: Circle())
    }.accessibilityLabel(label).shadow(color: .black.opacity(0.12), radius: 7, y: 3)
  }
  private func zoom(by factor: Double) { setMap(center, min(12, max(0.005, span * factor))) }
  private func setMap(_ coordinate: CLLocationCoordinate2D, _ delta: Double) {
    withAnimation(.easeInOut(duration: 0.25)) {
      center = coordinate
      span = delta
      position = .region(
        .init(center: coordinate, span: .init(latitudeDelta: delta, longitudeDelta: delta)))
    }
  }
  private func focusSavedArea() {
    setMap(
      profile.profile?.coordinate ?? location.region.center, profile.profile == nil ? 0.24 : 0.12)
  }
  private func refreshNotices() async {
    let shared = await BackendService.shared.fetchActiveNotices()
    notices.mergeShared(shared)
    await PushSync.shared.sync()
    if purchases.isPro
      && Bundle.main.object(forInfoDictionaryKey: "PushDeliveryReady") as? Bool != true
    {
      for update in shared { monitoring.notifyIfNeeded(for: update) }
    }
  }
}

private struct Pin: View {
  let category: SafetyCategory
  var body: some View {
    Image(systemName: category.symbol).font(.caption.bold()).foregroundStyle(.white).padding(10)
      .background(category.tint, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3))
      .shadow(radius: 4)
  }
}
private struct Filter: View {
  let title: String
  let active: Bool
  let tint: Color
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title).font(.caption.bold()).padding(.horizontal, 11).padding(.vertical, 8).background(
        active ? tint : tint.opacity(0.10), in: Capsule()
      ).foregroundStyle(active ? .white : tint)
    }
  }
}
private struct Nav: View {
  let icon: String
  let text: String
  let active: Bool
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: icon)
        Text(text).font(.caption2.bold())
      }.foregroundStyle(active ? .blue : .secondary).frame(maxWidth: .infinity).padding(
        .vertical, 7
      ).background(active ? Color.weywellMist : .clear, in: Capsule())
    }
  }
}

private struct Detail: View {
  let update: SafetyUpdate
  let route: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var photoURL: URL?

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Pin(category: update.category)
          Text(update.title).font(.title2.bold())
        }
        if let photoURL {
          AsyncImage(url: photoURL) { phase in
            if let image = phase.image {
              image.resizable().scaledToFill()
            } else {
              RoundedRectangle(cornerRadius: 16).fill(Color.weywellMist).overlay(ProgressView())
            }
          }.frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 16))
        }
        Divider()
        Label("Reported \(update.timestamp)", systemImage: "clock")
        Label(update.expiryText, systemImage: "hourglass").foregroundStyle(.orange)
        Label(update.locationText, systemImage: "mappin.and.ellipse")
        Text(update.detail).foregroundStyle(.secondary)
        Spacer()
        Button("Check a route") {
          dismiss()
          route()
        }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
      }.padding(22).navigationTitle("Local context")
        .task {
          if let path = update.photoPath {
            photoURL = await BackendService.shared.signedPhotoURL(for: path)
          }
        }
    }
  }
}

private struct RouteChecker: View {
  let origin: CLLocationCoordinate2D
  let originName: String
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var notices: NoticeStore
  @EnvironmentObject private var profile: ProfileStore
  @EnvironmentObject private var monitoring: MonitorManager
  @EnvironmentObject private var purchases: PurchaseManager
  @State private var destination = ""
  @State private var selectedDestination: AddressCandidate?
  @State private var matches: [AddressCandidate] = []
  @State private var foundRoute: MKRoute?
  @State private var routePosition: MapCameraPosition = .automatic
  @State private var routeError: String?
  @State private var searching = false
  @State private var checking = false
  @State private var savedRoute = false
  @State private var showingPlus = false

  private var selectedAddress: String? {
    guard let selectedDestination else { return nil }
    return [selectedDestination.title, selectedDestination.subtitle].filter { !$0.isEmpty }.joined(
      separator: ", ")
  }
  private var warnings: [SafetyUpdate] {
    guard let route = foundRoute else { return [] }
    return notices.activeUpdates.filter { route.polyline.distance(to: $0.coordinates) <= 1_200 }
  }

  var body: some View {
    ZStack {
      Color.weywellSky.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("PLAN WITH CONTEXT").font(.caption.bold()).tracking(1.4).foregroundStyle(
                .secondary)
              Text("Check a route").font(.system(size: 32, weight: .black, design: .rounded))
            }
            Spacer()
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark").font(.headline).frame(width: 42, height: 42).background(
                .white, in: Circle())
            }.foregroundStyle(.primary)
          }
          VStack(alignment: .leading, spacing: 13) {
            Label("FROM \(originName.uppercased())", systemImage: "circle.fill").font(
              .caption.bold()
            ).tracking(1)
            Text(profile.profile?.address ?? "The centre of the map you were viewing").font(
              .subheadline
            ).foregroundStyle(.secondary)
            Divider()
            Text("WHERE ARE YOU GOING?").font(.caption.bold()).tracking(1)
            TextField("Street address, suburb or city", text: $destination)
              .textInputAutocapitalization(.words)
              .padding(.horizontal, 14).padding(.vertical, 13)
              .background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
            Button {
              Task { await findDestination() }
            } label: {
              HStack {
                Spacer()
                if searching {
                  ProgressView().tint(.white)
                } else {
                  Text("Find destination").fontWeight(.bold)
                }
                Spacer()
              }
              .padding(.vertical, 14).background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
            }.foregroundStyle(.white).disabled(
              destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)

            if !matches.isEmpty {
              Text("CHOOSE A DESTINATION").font(.caption.bold()).tracking(1).foregroundStyle(
                .secondary)
              ForEach(matches) { candidate in
                Button {
                  selectedDestination = candidate
                  destination = [candidate.title, candidate.subtitle].filter { !$0.isEmpty }.joined(
                    separator: ", ")
                  matches = []
                  routeError = nil
                  foundRoute = nil
                } label: {
                  HStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(candidate.title).font(.subheadline.bold())
                      Text(candidate.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                  }.padding(12).background(
                    Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
                }.foregroundStyle(.primary)
              }
            }

            if selectedAddress == destination {
              Button {
                Task { await check() }
              } label: {
                HStack {
                  Spacer()
                  if checking {
                    ProgressView().tint(.white)
                  } else {
                    Label("Show driving route", systemImage: "car.fill").fontWeight(.bold)
                  }
                  Spacer()
                }
                .padding(.vertical, 15).background(
                  Color.blue, in: RoundedRectangle(cornerRadius: 14))
              }.foregroundStyle(.white).disabled(checking)
            }
            if let routeError {
              Label(routeError, systemImage: "exclamationmark.triangle.fill").font(.footnote)
                .foregroundStyle(.orange)
            }
          }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 23))

          if let route = foundRoute, let selectedDestination {
            VStack(alignment: .leading, spacing: 13) {
              Text("YOUR DRIVING ROUTE").font(.caption.bold()).tracking(1).foregroundStyle(
                .secondary)
              Map(position: $routePosition) {
                MapPolyline(route.polyline).stroke(.blue, lineWidth: 6)
                Marker("Start", coordinate: origin).tint(.blue)
                Marker("Destination", coordinate: selectedDestination.coordinate).tint(.green)
                ForEach(warnings) { update in
                  Marker(update.title, coordinate: update.coordinates).tint(.orange)
                }
              }.mapStyle(.standard(elevation: .flat, emphasis: .muted)).frame(height: 290)
                .clipShape(RoundedRectangle(cornerRadius: 16))
              Label(
                "\(max(1, Int(route.expectedTravelTime / 60))) min · \(String(format: "%.1f", route.distance / 1_000)) km",
                systemImage: "car.fill"
              ).font(.subheadline.bold())
              Text(
                warnings.isEmpty
                  ? "No current alerts along this route"
                  : "\(warnings.count) alert\(warnings.count == 1 ? "" : "s") along this route"
              ).font(.headline)
              ForEach(warnings) { update in
                Label("\(update.title) · \(update.expiryText)", systemImage: update.category.symbol)
                  .font(.subheadline)
              }
              if purchases.isPro {
                Button {
                  monitoring.addRoute(
                    name: "\(originName) to \(selectedDestination.title)", route: route)
                  savedRoute = true
                } label: {
                  Label(
                    savedRoute ? "Route saved to alerts" : "Follow this route",
                    systemImage: savedRoute ? "checkmark.circle.fill" : "bell.badge"
                  )
                  .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 13)
                  .background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
                }.disabled(savedRoute)
              } else {
                Button {
                  showingPlus = true
                } label: {
                  Label("Follow regular routes with Plus", systemImage: "bell.badge").font(
                    .subheadline.bold()
                  ).frame(maxWidth: .infinity).padding(.vertical, 13).background(
                    Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
                }
              }
            }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 23))
          }
        }.padding(20).padding(.bottom, 24)
      }
    }.sheet(isPresented: $showingPlus) { PlusView() }
  }

  private func findDestination() async {
    searching = true
    routeError = nil
    selectedDestination = nil
    foundRoute = nil
    savedRoute = false
    defer { searching = false }
    do {
      matches = try await profile.lookupAddress(destination)
      if matches.isEmpty {
        routeError = "No destination found. Add a street, suburb or city and try again."
      }
    } catch {
      matches = []
      routeError = "Address search is unavailable right now. Check your connection and try again."
    }
  }

  private func check() async {
    guard let selectedDestination, selectedAddress == destination else { return }
    checking = true
    foundRoute = nil
    savedRoute = false
    routeError = nil
    defer { checking = false }
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
    request.destination = MKMapItem(
      placemark: MKPlacemark(coordinate: selectedDestination.coordinate))
    request.transportType = .automobile
    do {
      guard let route = try await MKDirections(request: request).calculate().routes.first else {
        routeError = "No driving route was found for these places. Try another destination."
        return
      }
      foundRoute = route
      var region = MKCoordinateRegion(route.polyline.boundingMapRect)
      region.span.latitudeDelta = max(0.02, region.span.latitudeDelta * 1.35)
      region.span.longitudeDelta = max(0.02, region.span.longitudeDelta * 1.35)
      routePosition = .region(region)
    } catch {
      routeError = "Driving directions could not load right now. Try again in a moment."
    }
  }
}

extension MKPolyline {
  func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
    let target = MKMapPoint(coordinate)
    let vertices = points()
    guard pointCount > 1 else { return .infinity }
    var shortest = CLLocationDistance.infinity
    for index in 1..<pointCount {
      let a = vertices[index - 1]
      let b = vertices[index]
      let dx = b.x - a.x
      let dy = b.y - a.y
      let lengthSquared = dx * dx + dy * dy
      let fraction =
        lengthSquared == 0
        ? 0 : max(0, min(1, ((target.x - a.x) * dx + (target.y - a.y) * dy) / lengthSquared))
      let nearest = MKMapPoint(x: a.x + fraction * dx, y: a.y + fraction * dy)
      shortest = min(shortest, target.distance(to: nearest))
    }
    return shortest
  }
}

private struct ReportSheet: View {
  let center: CLLocationCoordinate2D
  @ObservedObject var location: LocationManager
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var notices: NoticeStore
  @State private var category: SafetyCategory?
  @State private var place = ""
  @State private var reportedCoordinate: CLLocationCoordinate2D
  @State private var verifiedPlace = ""
  @State private var placeMatches: [AddressCandidate] = []
  @State private var isSearchingPlace = false
  @State private var isVerifyingPin = false
  @State private var locationMessage: String?
  @State private var showingPinPicker = false
  @State private var sending = false
  @State private var done = false
  @State private var error: String?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var photoData: Data?
  @State private var photoLoading = false
  @State private var photoError: String?

  init(center: CLLocationCoordinate2D, location: LocationManager) {
    self.center = center
    self.location = location
    _reportedCoordinate = State(initialValue: center)
  }

  private var locationIsVerified: Bool {
    !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && verifiedPlace == place
  }

  var body: some View {
    ZStack {
      Color.weywellSky.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("A HEADS-UP HELPS EVERYONE").font(.caption.bold()).tracking(1.3).foregroundStyle(
                Color.coral)
              Text("Share what you saw").font(.system(size: 32, weight: .black, design: .rounded))
            }
            Spacer()
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark").font(.headline).frame(width: 42, height: 42).background(
                .white, in: Circle())
            }.foregroundStyle(.primary)
          }
          VStack(alignment: .leading, spacing: 14) {
            Text("WHAT HAPPENED?").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
              ForEach(SafetyCategory.allCases) { item in
                Button {
                  category = item
                } label: {
                  Label(item.rawValue, systemImage: item.symbol).font(.caption.bold()).frame(
                    maxWidth: .infinity, minHeight: 62
                  )
                  .background(
                    item.tint.opacity(category == item ? 0.18 : 0.08),
                    in: RoundedRectangle(cornerRadius: 14)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 14).stroke(
                      category == item ? item.tint : .clear, lineWidth: 2))
                }.foregroundStyle(.primary)
              }
            }
            Text("WHERE DID IT HAPPEN?").font(.caption.bold()).tracking(1).foregroundStyle(
              .secondary
            ).padding(.top, 5)
            TextField("Road or public place nearby", text: $place)
              .textContentType(.streetAddressLine1)
              .padding(.horizontal, 14).padding(.vertical, 13)
              .background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
              .onChange(of: place) { _, newValue in
                if verifiedPlace != newValue { verifiedPlace = "" }
              }
            Map(
              position: .constant(
                .region(
                  .init(
                    center: reportedCoordinate,
                    span: .init(latitudeDelta: 0.018, longitudeDelta: 0.018))))
            ) {
              Annotation("Alert location", coordinate: reportedCoordinate, anchor: .bottom) {
                Image(systemName: "mappin.and.ellipse").font(.title2.bold()).foregroundStyle(
                  Color.coral
                ).padding(8).background(.white, in: Circle()).shadow(radius: 4)
              }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .frame(height: 145).clipShape(RoundedRectangle(cornerRadius: 14)).allowsHitTesting(
              false)
            HStack(spacing: 9) {
              Button {
                showingPinPicker = true
              } label: {
                Label("Adjust map pin", systemImage: "mappin.and.ellipse").font(.caption.bold())
                  .frame(maxWidth: .infinity).padding(.vertical, 11).background(
                    Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
              }
              Button {
                Task { await searchPlace() }
              } label: {
                if isSearchingPlace {
                  ProgressView().frame(maxWidth: .infinity).padding(.vertical, 11)
                } else {
                  Label("Verify place", systemImage: "checkmark.magnifyingglass").font(
                    .caption.bold()
                  ).frame(maxWidth: .infinity).padding(.vertical, 11)
                }
              }.background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
                .disabled(
                  place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearchingPlace)
            }
            if location.currentLocation != nil {
              Button {
                Task { await useCurrentLocation() }
              } label: {
                Label("Use my current location", systemImage: "location.fill").font(.caption.bold())
              }
            }
            if !placeMatches.isEmpty {
              VStack(alignment: .leading, spacing: 7) {
                Text("CHOOSE THE MATCHING PLACE").font(.caption2.bold()).tracking(0.8)
                  .foregroundStyle(.secondary)
                ForEach(placeMatches) { match in
                  Button {
                    selectVerifiedPlace(match)
                  } label: {
                    VStack(alignment: .leading, spacing: 2) {
                      Text(match.title).font(.subheadline.weight(.semibold))
                      Text(match.subtitle).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(
                      Color.weywellMist, in: RoundedRectangle(cornerRadius: 11))
                  }.foregroundStyle(.primary)
                }
              }
            }
            if let locationMessage {
              Label(
                locationMessage,
                systemImage: locationIsVerified ? "checkmark.circle.fill" : "info.circle.fill"
              )
              .font(.footnote).foregroundStyle(
                locationIsVerified ? Color.weywellMint : Color.secondary)
            }
            if !locationIsVerified {
              Button {
                Task { await confirmPinAndPlace() }
              } label: {
                HStack(spacing: 8) {
                  if isVerifyingPin { ProgressView() }
                  Label("Confirm this pin and place", systemImage: "checkmark.circle")
                }
                .font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
              }.disabled(
                place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || !isSouthAfrican(reportedCoordinate) || isVerifyingPin)
            }
            Text(
              "Check the pin matches the road or public place, not the reporter’s home. Keep names, private addresses and identifying details out of the report."
            ).font(.footnote).foregroundStyle(.secondary)
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
              Label(
                photoData == nil ? "Add a photo (optional)" : "Change photo",
                systemImage: "photo.badge.plus"
              )
              .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
              .background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
            }.disabled(sending || done)
            if photoLoading { ProgressView("Preparing photo…").font(.caption) }
            if let photoData, let image = UIImage(data: photoData) {
              Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity).frame(
                height: 150
              )
              .clipShape(RoundedRectangle(cornerRadius: 14)).overlay(alignment: .topTrailing) {
                Button {
                  self.photoData = nil
                  selectedPhoto = nil
                } label: {
                  Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(
                    .white, Color.weywellInk)
                }.padding(8).accessibilityLabel("Remove photo")
              }
            }
            Text("Photos help show road conditions. Avoid faces, number plates and private homes.")
              .font(.caption).foregroundStyle(.secondary)
            if let photoError {
              Label(photoError, systemImage: "exclamationmark.triangle.fill").font(.footnote)
                .foregroundStyle(.orange)
            }
            Button {
              Task { await submit() }
            } label: {
              HStack {
                Spacer()
                if sending {
                  ProgressView().tint(.white)
                } else {
                  Label("Send alert for review", systemImage: "megaphone.fill").fontWeight(.bold)
                }
                Spacer()
              }
              .padding(.vertical, 15).background(
                Color.coral, in: RoundedRectangle(cornerRadius: 15))
            }.foregroundStyle(.white).disabled(
              category == nil || !locationIsVerified || sending || done || photoLoading)
            if done {
              Label(
                "Thanks for looking out for your neighbours. Your update will appear after review.",
                systemImage: "heart.circle.fill"
              ).font(.footnote).foregroundStyle(Color.weywellMint)
            }
            if let error {
              Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote)
                .foregroundStyle(.orange)
            }
          }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 23))
          HStack(alignment: .top, spacing: 9) {
            Image(systemName: "person.2.fill").foregroundStyle(Color.coral)
            Text(
              "Shared by people here, reviewed before it appears. Road and safety updates last 24 hours; break-in context lasts 7 days."
            )
            .font(.footnote).foregroundStyle(Color.weywellInk.opacity(0.75))
          }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
            .white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        }.padding(20)
      }
    }
    .sheet(isPresented: $showingPinPicker) {
      PinLocationPicker(initialCoordinate: reportedCoordinate) { coordinate in
        reportedCoordinate = coordinate
        placeMatches = []
        verifiedPlace = ""
        locationMessage = "Pin moved. Verify the place or confirm the pin before sending."
        showingPinPicker = false
      }
    }
    .onChange(of: selectedPhoto) { _, item in
      guard let item else {
        photoData = nil
        photoError = nil
        return
      }
      photoLoading = true
      photoError = nil
      Task {
        defer { photoLoading = false }
        guard let original = try? await item.loadTransferable(type: Data.self),
          let image = UIImage(data: original)
        else {
          photoError = "Couldn’t read that photo. Please choose another."
          return
        }
        let maxDimension = max(image.size.width, image.size.height)
        let scale = min(1, 1280 / maxDimension)
        let size = CGSize(
          width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let optimized = renderer.jpegData(withCompressionQuality: 0.72) { _ in
          image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard optimized.count <= 5 * 1_024 * 1_024 else {
          photoError = "That photo is still too large. Choose a smaller image."
          return
        }
        photoData = optimized
      }
    }
  }

  private func submit() async {
    guard let category, locationIsVerified, isSouthAfrican(reportedCoordinate) else { return }
    sending = true
    error = nil
    let update = notices.makePending(
      category: category, locationText: place.trimmingCharacters(in: .whitespacesAndNewlines),
      coordinates: reportedCoordinate)
    let success = await BackendService.shared.submit(update, photoData: photoData)
    sending = false
    if success {
      done = true
    } else {
      error = "Couldn’t send this report. Check your connection and try again."
    }
  }

  private func searchPlace() async {
    isSearchingPlace = true
    defer { isSearchingPlace = false }
    placeMatches = await (try? ProfileStore.shared.lookupAddress(place)) ?? []
    locationMessage =
      placeMatches.isEmpty
      ? "No matching South African place found. Adjust the wording or choose the pin on the map."
      : "Choose the result that matches the incident location."
  }

  private func selectVerifiedPlace(_ match: AddressCandidate) {
    reportedCoordinate = match.coordinate
    place = [match.title, match.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    verifiedPlace = place
    placeMatches = []
    locationMessage = "Place matched on the map. Check that the pin is right before sending."
  }

  private func useCurrentLocation() async {
    guard let current = location.currentLocation, isSouthAfrican(current.coordinate) else {
      locationMessage =
        "Current location is unavailable or outside South Africa. Choose the pin on the map instead."
      return
    }
    reportedCoordinate = current.coordinate
    placeMatches = []
    verifiedPlace = ""
    do {
      let marks = try await CLGeocoder().reverseGeocodeLocation(current)
      if let mark = marks.first, mark.isoCountryCode == "ZA" {
        let publicPlace = [
          mark.thoroughfare, mark.subLocality, mark.locality, mark.administrativeArea,
        ]
        .compactMap { $0 }.filter { !$0.isEmpty }
        if !publicPlace.isEmpty { place = publicPlace.joined(separator: ", ") }
        locationMessage =
          "Current position selected (about ±\(Int(max(0, current.horizontalAccuracy))) m). Check and confirm the incident location."
      } else {
        locationMessage =
          "The current position could not be verified as being in South Africa. Choose a South African map result instead."
      }
    } catch {
      locationMessage =
        "Pin set to your current position, but could not be verified. Search for a South African place before sending."
    }
  }

  private func confirmPinAndPlace() async {
    guard isSouthAfrican(reportedCoordinate),
      !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    isVerifyingPin = true
    defer { isVerifyingPin = false }
    do {
      let marks = try await CLGeocoder().reverseGeocodeLocation(
        CLLocation(latitude: reportedCoordinate.latitude, longitude: reportedCoordinate.longitude))
      guard marks.first?.isoCountryCode == "ZA" else {
        verifiedPlace = ""
        locationMessage =
          "That pin could not be confirmed as a South African location. Adjust it or choose a search result."
        return
      }
      verifiedPlace = place
      locationMessage = "South African map pin and place confirmed by you."
    } catch {
      verifiedPlace = ""
      locationMessage =
        "Couldn’t verify that pin right now. Choose a matching place result or try again."
    }
  }

  private func isSouthAfrican(_ coordinate: CLLocationCoordinate2D) -> Bool {
    coordinate.latitude.isFinite && coordinate.longitude.isFinite
      && (-35 ... -22).contains(coordinate.latitude) && (16...33).contains(coordinate.longitude)
  }
}

private struct PinLocationPicker: View {
  let initialCoordinate: CLLocationCoordinate2D
  let onConfirm: (CLLocationCoordinate2D) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var camera: MapCameraPosition
  @State private var pinCoordinate: CLLocationCoordinate2D

  init(
    initialCoordinate: CLLocationCoordinate2D, onConfirm: @escaping (CLLocationCoordinate2D) -> Void
  ) {
    self.initialCoordinate = initialCoordinate
    self.onConfirm = onConfirm
    _pinCoordinate = State(initialValue: initialCoordinate)
    _camera = State(
      initialValue: .region(
        .init(center: initialCoordinate, span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025))))
  }

  var body: some View {
    NavigationStack {
      Map(position: $camera) {}
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .overlay {
          VStack(spacing: 4) {
            Image(systemName: "mappin").font(.system(size: 34, weight: .bold)).foregroundStyle(
              Color.coral)
            Circle().fill(Color.coral.opacity(0.25)).frame(width: 18, height: 18).overlay(
              Circle().stroke(.white, lineWidth: 2))
          }.offset(y: -24).allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
          Label("Move the map until the pin marks the incident", systemImage: "hand.draw")
            .font(.caption.bold()).padding(10).background(.white, in: Capsule()).padding(.top, 14)
        }
        .onMapCameraChange(frequency: .onEnd) { context in pinCoordinate = context.region.center }
        .safeAreaInset(edge: .bottom) {
          Button {
            onConfirm(pinCoordinate)
          } label: {
            Label("Use this location", systemImage: "checkmark.circle.fill").font(.headline)
              .frame(maxWidth: .infinity).padding(.vertical, 15).background(
                Color.coral, in: RoundedRectangle(cornerRadius: 15)
              ).foregroundStyle(.white)
          }.padding(16).background(.regularMaterial)
        }
        .navigationTitle("Set alert location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
    }
  }
}

private struct AlertCentre: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var monitoring: MonitorManager
  @EnvironmentObject private var notices: NoticeStore
  @EnvironmentObject private var profile: ProfileStore
  @EnvironmentObject private var purchases: PurchaseManager
  @ObservedObject private var push = PushSync.shared
  @State private var name = ""
  @State private var radius = 20.0
  @State private var showingPlus = false

  private var nearby: [SafetyUpdate] {
    notices.activeUpdates.filter { update in
      let matchedWatch = purchases.isPro && !monitoring.matchingMonitorNames(for: update).isEmpty
      guard let home = profile.profile?.coordinate else { return matchedWatch }
      let distance = CLLocation(latitude: home.latitude, longitude: home.longitude)
        .distance(
          from: CLLocation(
            latitude: update.coordinates.latitude, longitude: update.coordinates.longitude))
      return matchedWatch || distance <= radius * 1_000
    }
  }

  var body: some View {
    ZStack {
      Color.weywellSky.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("CURRENT, NEAR YOU").font(.caption.bold()).tracking(1.3).foregroundStyle(
                .secondary)
              Text("Alerts").font(.system(size: 32, weight: .black, design: .rounded))
            }
            Spacer()
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark").font(.headline).frame(width: 42, height: 42).background(
                .white, in: Circle())
            }.foregroundStyle(.primary)
          }

          VStack(alignment: .leading, spacing: 12) {
            Text("AROUND YOUR SAVED AREA").font(.caption.bold()).tracking(1).foregroundStyle(
              .secondary)
            Text(
              profile.profile?.address
                ?? "Add your home address in Profile to see local notices here."
            ).font(.subheadline)
            HStack {
              Text("Within \(Int(radius)) km").font(.subheadline.bold())
              Spacer()
              Text("\(nearby.count) current").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Slider(value: $radius, in: 5...60, step: 5)
            if nearby.isEmpty {
              Label(
                profile.profile == nil
                  ? "Set a home area to get started"
                  : "No active notices match this area right now",
                systemImage: "checkmark.circle.fill"
              )
              .font(.subheadline).foregroundStyle(Color.weywellMint).padding(12).frame(
                maxWidth: .infinity, alignment: .leading
              ).background(Color.weywellMint.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            } else {
              ForEach(nearby) { update in
                HStack(alignment: .top, spacing: 12) {
                  Pin(category: update.category)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(update.title).font(.subheadline.bold())
                    Text("\(update.locationText) · \(update.expiryText)").font(.caption)
                      .foregroundStyle(.secondary)
                    let matches =
                      purchases.isPro ? monitoring.matchingMonitorNames(for: update) : []
                    if !matches.isEmpty {
                      Text("Matches \(matches.joined(separator: ", "))").font(.caption2.bold())
                        .foregroundStyle(.blue)
                    }
                  }
                }.padding(.vertical, 5)
              }
            }
          }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 23))

          VStack(alignment: .leading, spacing: 11) {
            Label("NOTIFICATIONS", systemImage: "bell.badge").font(.caption.bold()).tracking(1)
              .foregroundStyle(Color.amber)
            Text(push.status).font(.footnote).foregroundStyle(.secondary)
            if Bundle.main.object(forInfoDictionaryKey: "PushDeliveryReady") as? Bool != true {
              Text(
                "Background delivery is being connected. You can always see current notices here when you open Weywell."
              ).font(.footnote).foregroundStyle(.secondary)
            }
            if monitoring.notificationStatus == .authorized {
              Label("Notifications allowed", systemImage: "checkmark.circle.fill").font(
                .subheadline.bold()
              ).foregroundStyle(.green)
            } else {
              Button("Allow notifications") { monitoring.requestPermission() }.font(
                .subheadline.bold()
              ).padding(.vertical, 10)
            }
          }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
            .white, in: RoundedRectangle(cornerRadius: 23))

          VStack(alignment: .leading, spacing: 12) {
            Text("FOLLOW PLACES & ROUTES").font(.caption.bold()).tracking(1).foregroundStyle(
              Color.purple)
            Text("Your everyday places, with a little help from the community.").font(.subheadline)
              .foregroundStyle(.secondary)
            if purchases.isPro {
              if profile.profile != nil {
                TextField("Name this area, e.g. Home", text: $name).padding(.horizontal, 14)
                  .padding(.vertical, 12).background(
                    Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
                Button("Follow this area") {
                  if let coordinate = profile.profile?.coordinate {
                    monitoring.add(
                      name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: .area,
                      radius: Int(radius), coordinate: coordinate)
                    name = ""
                  }
                }.font(.subheadline.bold()).disabled(
                  name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              } else {
                Text("Save a home address in Profile first.").font(.footnote).foregroundStyle(
                  .secondary)
              }
            } else {
              Button {
                showingPlus = true
              } label: {
                Label("Explore Plus controls", systemImage: "slider.horizontal.3").font(
                  .subheadline.bold())
              }
            }
            ForEach(purchases.isPro ? monitoring.monitors : []) { item in
              HStack(spacing: 8) {
                Image(systemName: item.kind == .route ? "car.fill" : "mappin.circle.fill")
                  .foregroundStyle(item.kind == .route ? Color.purple : Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                  Text(item.name).font(.subheadline.bold())
                  Text(item.kind == .route ? "Route watch" : "Area · \(item.radiusKilometres) km")
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                  item.name,
                  isOn: Binding(get: { item.isEnabled }, set: { _ in monitoring.toggle(item) })
                ).labelsHidden()
                Button {
                  monitoring.delete(item)
                } label: {
                  Image(systemName: "trash").foregroundStyle(.red).frame(width: 32, height: 32)
                }.accessibilityLabel("Remove \(item.name)")
              }.padding(.vertical, 6)
            }
          }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
            .white, in: RoundedRectangle(cornerRadius: 23))
        }.padding(20).padding(.bottom, 24)
      }
    }.onAppear { monitoring.refreshPermission() }
      .sheet(isPresented: $showingPlus) { PlusView() }
  }
}

private struct ProfileView: View {
  let mapCenter: CLLocationCoordinate2D
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var profile: ProfileStore
  @EnvironmentObject private var monitoring: MonitorManager
  @State private var name = ""
  @State private var address = ""
  @State private var remove = false
  @State private var showingModeration = false

  var body: some View {
    ZStack {
      Color.weywellSky.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
              Text("YOUR WEYWELL").font(.caption.bold()).tracking(1.4).foregroundStyle(.secondary)
              Text("Profile").font(.system(size: 32, weight: .black, design: .rounded))
            }
            Spacer()
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark").font(.headline).frame(width: 42, height: 42).background(
                .white, in: Circle())
            }.foregroundStyle(.primary)
          }

          VStack(alignment: .leading, spacing: 14) {
            Label("YOUR EVERYDAY AREA", systemImage: "mappin.and.ellipse").font(.caption.bold())
              .tracking(1)
            Text("Save the place Weywell should return to and use for local alerts.").font(
              .subheadline
            ).foregroundStyle(.secondary)
            field("First name (optional)", text: $name)
            field("Street number, street, suburb, city", text: $address)
              .onChange(of: address) { _, _ in profile.clearMatches() }
            Button {
              Task { await profile.search(address: address) }
            } label: {
              HStack {
                Spacer()
                if profile.isResolving {
                  ProgressView().tint(.white)
                } else {
                  Text("Find my address").fontWeight(.bold)
                }
                Spacer()
              }
              .padding(.vertical, 15).background(Color.blue, in: RoundedRectangle(cornerRadius: 15))
            }.foregroundStyle(.white).disabled(
              address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || profile.isResolving
            )

            if !profile.addressMatches.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                Text("MATCHING ADDRESSES").font(.caption.bold()).tracking(1).foregroundStyle(
                  .secondary)
                ForEach(profile.addressMatches) { candidate in
                  Button {
                    profile.save(name: name, candidate: candidate)
                  } label: {
                    HStack(spacing: 10) {
                      Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(.blue)
                      VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.title).font(.subheadline.bold())
                        Text(candidate.subtitle).font(.caption).foregroundStyle(.secondary)
                      }
                      Spacer()
                      Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(
                        .secondary)
                    }.padding(12).background(
                      Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
                  }.foregroundStyle(.primary)
                }
              }
            }

            Divider()
            Text("ADDRESS NOT SHOWING UP?").font(.caption.bold()).tracking(1).foregroundStyle(
              .secondary)
            Text(
              "If search is temporarily unavailable, you can place the map over your area and save that position. This is less precise than selecting an address."
            ).font(.footnote).foregroundStyle(.secondary)
            Button {
              profile.saveMapArea(name: name, coordinate: mapCenter)
            } label: {
              Label("Use the area currently on the map", systemImage: "scope").font(
                .subheadline.bold()
              ).frame(maxWidth: .infinity).padding(.vertical, 12).background(
                Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
            }.foregroundStyle(.primary)

            if let saved = profile.profile {
              Label(saved.address, systemImage: "checkmark.seal.fill").font(
                .footnote.weight(.semibold)
              ).foregroundStyle(.green)
            }
            if let message = profile.message {
              Text(message).font(.footnote).foregroundStyle(
                profile.profile == nil ? .red : .secondary)
            }
          }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 23))

          if profile.profile != nil {
            VStack(alignment: .leading, spacing: 10) {
              Text("PROFILE & PRIVACY").font(.caption.bold()).tracking(1).foregroundStyle(
                .secondary)
              Text(
                "Your saved address stays on this device. Reports are never tied to this profile."
              ).font(.footnote).foregroundStyle(.secondary)
              Button("Delete profile from this device", role: .destructive) { remove = true }.font(
                .subheadline.bold())
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
              .white, in: RoundedRectangle(cornerRadius: 23))
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("COMMUNITY CARE").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            Text(
              "Reports are checked before they appear on the map. Approved updates are temporary and should be treated as community context, not verified crime statistics."
            )
            .font(.footnote).foregroundStyle(.secondary)
            Button {
              showingModeration = true
            } label: {
              Label("Moderator sign-in", systemImage: "checkmark.shield.fill")
                .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
            }.foregroundStyle(.blue)
          }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
            .white, in: RoundedRectangle(cornerRadius: 23))
        }.padding(20).padding(.bottom, 24)
      }
    }
    .onAppear {
      name = profile.profile?.name ?? ""
      address = profile.profile?.address ?? ""
    }
    .alert("Delete your Weywell profile?", isPresented: $remove) {
      Button("Delete", role: .destructive) {
        Task { await PushSync.shared.deleteServerData() }
        profile.deleteProfile()
        monitoring.deleteAll(sync: false)
        name = ""
        address = ""
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Your saved address and local monitoring alerts will be removed from this device.")
    }
    .sheet(isPresented: $showingModeration) { ModerationView() }
  }

  private func field(_ title: String, text: Binding<String>) -> some View {
    TextField(title, text: text).padding(.horizontal, 14).padding(.vertical, 13).background(
      Color.weywellMist, in: RoundedRectangle(cornerRadius: 13)
    ).textInputAutocapitalization(.words)
  }
}

private struct ModerationView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var backend = BackendService.shared
  @State private var email = ""
  @State private var password = ""
  @State private var reports: [ModerationReport] = []
  @State private var loading = false
  @State private var workingID: UUID?
  @State private var error: String?
  @State private var rejectedReport: ModerationReport?
  @State private var recoveryMessage: String?
  @State private var sendingRecovery = false

  var body: some View {
    NavigationStack {
      ZStack {
        Color.weywellSky.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text("TRUSTED COMMUNITY REVIEW").font(.caption.bold()).tracking(1.2)
                  .foregroundStyle(.secondary)
                Text("Report queue").font(.system(size: 31, weight: .black, design: .rounded))
              }
              Spacer()
              Button {
                dismiss()
              } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 42, height: 42).background(
                  .white, in: Circle())
              }.foregroundStyle(.primary)
            }
            if backend.isModeratorSignedIn {
              queueContent
            } else {
              signInContent
            }
          }.padding(20)
        }
      }
      .navigationBarHidden(true)
      .task { if backend.isModeratorSignedIn { await loadQueue() } }
      .confirmationDialog(
        "Reject this report?",
        isPresented: Binding(
          get: { rejectedReport != nil }, set: { if !$0 { rejectedReport = nil } }),
        titleVisibility: .visible
      ) {
        Button("Reject report", role: .destructive) {
          guard let report = rejectedReport else { return }
          rejectedReport = nil
          Task { await review(report, approve: false) }
        }
        Button("Cancel", role: .cancel) { rejectedReport = nil }
      } message: {
        Text("It will stay off the public map and its photo will remain private.")
      }
    }
  }

  private var signInContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Private moderator access", systemImage: "lock.shield.fill").font(.headline)
        .foregroundStyle(.blue)
      Text(
        "Only accounts explicitly added to Weywell’s moderator list can view or action reports. If you’re the project owner, finish the one-time setup in MODERATION_SETUP.md first."
      )
      .font(.subheadline).foregroundStyle(.secondary)
      TextField("Moderator email", text: $email).textContentType(.username).keyboardType(
        .emailAddress
      )
      .textInputAutocapitalization(.never).autocorrectionDisabled().padding(13).background(
        Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
      SecureField("Password", text: $password).textContentType(.password).padding(13).background(
        Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
      Button {
        Task { await signIn() }
      } label: {
        HStack {
          Spacer()
          if loading {
            ProgressView().tint(.white)
          } else {
            Text("Sign in to review").fontWeight(.bold)
          }
          Spacer()
        }
        .padding(.vertical, 15).background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
      }.foregroundStyle(.white).disabled(loading || email.isEmpty || password.isEmpty)
      Button {
        Task {
          sendingRecovery = true
          defer { sendingRecovery = false }
          do {
            try await backend.sendModeratorPasswordRecovery(email: email)
            recoveryMessage =
              "If this email belongs to a Weywell account, a reset link is on its way."
          } catch {
            recoveryMessage = "Couldn’t send a reset link. Check your connection and try again."
          }
        }
      } label: {
        HStack(spacing: 7) {
          if sendingRecovery { ProgressView() }
          Text("Forgot password?").font(.subheadline.weight(.semibold))
        }.frame(maxWidth: .infinity).padding(.vertical, 7)
      }
      .foregroundStyle(.blue).disabled(
        sendingRecovery || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if let recoveryMessage { Text(recoveryMessage).font(.footnote).foregroundStyle(.secondary) }
      if let message = backend.moderatorError ?? error {
        Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote)
          .foregroundStyle(.orange)
      }
    }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 22))
  }

  private var queueContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("\(reports.count) awaiting review").font(.headline)
          Text("Approval makes an active report visible to everyone.").font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          Task { await loadQueue() }
        } label: {
          if loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
        }.accessibilityLabel("Refresh report queue")
      }
      if let error {
        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(
          .orange)
      }
      if reports.isEmpty && !loading {
        ContentUnavailableView(
          "Queue is clear", systemImage: "checkmark.seal",
          description: Text("New community reports will appear here for review.")
        )
        .padding(.vertical, 12).background(.white, in: RoundedRectangle(cornerRadius: 22))
      }
      ForEach(reports) { report in
        ModerationReportCard(
          report: report, isWorking: workingID == report.id,
          approve: { Task { await review(report, approve: true) } },
          reject: { rejectedReport = report })
      }
      Button("Sign out") {
        backend.moderatorSignOut()
        reports = []
        password = ""
        error = nil
      }.font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 10)
    }.padding(18).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
  }

  private func signIn() async {
    loading = true
    error = nil
    defer { loading = false }
    if await backend.moderatorSignIn(email: email, password: password) {
      password = ""
      await loadQueue()
    }
  }

  private func loadQueue() async {
    loading = true
    error = nil
    defer { loading = false }
    do { reports = try await backend.fetchPendingReports() } catch {
      self.error = "Couldn’t load the moderation queue. Check your access and connection."
    }
  }

  private func review(_ report: ModerationReport, approve: Bool) async {
    workingID = report.id
    error = nil
    defer { workingID = nil }
    do {
      try await backend.reviewReport(report, approve: approve)
      reports.removeAll { $0.id == report.id }
    } catch {
      self.error =
        "Couldn’t update this report. It may already have been reviewed; refresh the queue."
    }
  }
}

struct PasswordResetView: View {
  @Environment(\.dismiss) private var dismiss
  let accessToken: String
  let onPasswordChanged: () -> Void
  @State private var password = ""
  @State private var confirmation = ""
  @State private var saving = false
  @State private var error: String?

  private var passwordsMatch: Bool { !password.isEmpty && password == confirmation }

  var body: some View {
    NavigationStack {
      ZStack {
        Color.weywellSky.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
          Label("SECURE YOUR ACCOUNT", systemImage: "lock.shield.fill")
            .font(.caption.bold()).tracking(1.2).foregroundStyle(.blue)
          Text("Set a new password")
            .font(.system(size: 31, weight: .black, design: .rounded))
          Text("Choose a password you’ll use to sign in to Weywell’s moderator tools.")
            .font(.subheadline).foregroundStyle(.secondary)
          SecureField("New password (8+ characters)", text: $password)
            .textContentType(.newPassword).textInputAutocapitalization(.never)
            .padding(14).background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
          SecureField("Confirm new password", text: $confirmation)
            .textContentType(.newPassword).textInputAutocapitalization(.never)
            .padding(14).background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 13))
          if let error { Text(error).font(.footnote).foregroundStyle(.red) }
          Button {
            Task { await savePassword() }
          } label: {
            HStack {
              Spacer()
              if saving {
                ProgressView().tint(.white)
              } else {
                Text("Save password").fontWeight(.bold)
              }
              Spacer()
            }
            .padding(.vertical, 15).background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
          }
          .foregroundStyle(.white)
          .disabled(saving || password.count < 8 || !passwordsMatch)
          Spacer(minLength: 0)
        }
        .padding(22).padding(.top, 24)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .padding(20)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func savePassword() async {
    saving = true
    error = nil
    defer { saving = false }
    do {
      try await BackendService.shared.setRecoveredPassword(
        accessToken: accessToken, newPassword: password)
      onPasswordChanged()
      dismiss()
    } catch {
      self.error =
        "The reset link may have expired or already been used. Request a new one and try again."
    }
  }
}

private struct ModerationReportCard: View {
  let report: ModerationReport
  let isWorking: Bool
  let approve: () -> Void
  let reject: () -> Void
  @State private var photoURL: URL?

  private var categoryTitle: String {
    switch report.category {
    case "route_disruption": "Road closure / protest"
    case "unsafe_behaviour": "Unsafe behaviour"
    case "crime_reported": "Crime reported"
    case "neighbourhood": "Recent break-ins"
    default: "Community report"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(categoryTitle.uppercased()).font(.caption.bold()).tracking(0.8).foregroundStyle(
            Color.coral)
          Text(report.title).font(.headline)
        }
        Spacer()
        Text(report.reportedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
      }
      Label(report.locationText, systemImage: "mappin.and.ellipse").font(.subheadline)
      Text(report.detail).font(.subheadline).foregroundStyle(.secondary)
      if let photoURL {
        AsyncImage(url: photoURL) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            ProgressView().frame(maxWidth: .infinity).frame(height: 180)
          }
        }.frame(maxWidth: .infinity).frame(height: 180).clipShape(
          RoundedRectangle(cornerRadius: 13))
      }
      HStack(spacing: 10) {
        Button(action: reject) {
          Label("Reject", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity).padding(
            .vertical, 11
          ).background(Color.weywellMist, in: RoundedRectangle(cornerRadius: 12))
        }.foregroundStyle(.red).disabled(isWorking)
        Button(action: approve) {
          Label("Approve", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).padding(
            .vertical, 11
          ).background(Color.weywellMint, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(
            .white)
        }.disabled(isWorking)
      }
      if isWorking { ProgressView().frame(maxWidth: .infinity) }
    }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
      .task(id: report.photoPath) {
        if let path = report.photoPath {
          photoURL = await BackendService.shared.moderatorPhotoURL(for: path)
        }
      }
  }
}

private struct PlusView: View {
  @EnvironmentObject private var purchases: PurchaseManager
  @Environment(\.dismiss) private var dismiss

  private var price: String? {
    guard let product = purchases.offering?.availablePackages.first?.storeProduct else {
      return nil
    }
    guard let period = product.subscriptionPeriod else { return product.localizedPriceString }
    let unit: String
    switch period.unit {
    case .day: unit = period.value == 1 ? "day" : "\(period.value) days"
    case .week: unit = period.value == 1 ? "week" : "\(period.value) weeks"
    case .month: unit = period.value == 1 ? "month" : "\(period.value) months"
    case .year: unit = period.value == 1 ? "year" : "\(period.value) years"
    @unknown default: return product.localizedPriceString
    }
    return "\(product.localizedPriceString) per \(unit)"
  }

  var body: some View {
    ZStack {
      Color.weywellSky.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("MORE CONTROL, WHEN YOU WANT IT").font(.caption.bold()).tracking(1.1)
                .foregroundStyle(.secondary)
              Text("Weywell Plus").font(.system(size: 32, weight: .black, design: .rounded))
            }
            Spacer()
            Button {
              dismiss()
            } label: {
              Image(systemName: "xmark").font(.headline).frame(width: 42, height: 42).background(
                .white, in: Circle())
            }.foregroundStyle(.primary)
          }

          VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "slider.horizontal.3").font(.system(size: 29, weight: .semibold))
              .foregroundStyle(.white).frame(width: 56, height: 56).background(
                Color.purple, in: RoundedRectangle(cornerRadius: 16))
            Text("See the updates that matter to you.").font(.title2.bold())
            Text(
              "The map, current notices, community reporting and route checks are free. Plus adds focused controls for the places and journeys you follow."
            ).font(.subheadline).foregroundStyle(.secondary)
          }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
            LinearGradient(
              colors: [.white, Color.purple.opacity(0.09)], startPoint: .topLeading,
              endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 23))

          VStack(alignment: .leading, spacing: 18) {
            feature(
              "line.3.horizontal.decrease.circle.fill", "Filter the map",
              "Show just road closures, unsafe behaviour, crime notices or break-in context.",
              tint: .coral)
            feature(
              "mappin.and.ellipse", "Follow your area",
              "Save an area and choose the distance you want to keep an eye on.", tint: .blue)
            feature(
              "point.topleft.down.curvedto.point.bottomright.up", "Follow a regular route",
              "Keep a route in your saved watches and see notices near its roads.", tint: .purple)
          }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 23))

          if purchases.isPro {
            Label("Weywell Plus is active", systemImage: "checkmark.seal.fill").font(.headline)
              .foregroundStyle(.blue).padding(18).frame(maxWidth: .infinity).background(
                .white, in: RoundedRectangle(cornerRadius: 18))
          } else {
            VStack(alignment: .leading, spacing: 10) {
              Text(price ?? "Checking the available offer…").font(.headline)
              Text(
                purchases.isTestStore
                  ? "Development test purchase. No real charge."
                  : "The App Store shows the full price and terms before you confirm."
              ).font(.caption).foregroundStyle(.secondary)
              Button {
                purchases.purchase()
              } label: {
                Text("Continue with Plus").font(.headline).frame(maxWidth: .infinity).padding(
                  .vertical, 16
                ).background(Color.blue, in: RoundedRectangle(cornerRadius: 15))
              }.foregroundStyle(.white).disabled(
                purchases.offering?.availablePackages.isEmpty != false)
              Button("Restore purchases") { purchases.restore() }.font(.subheadline.bold()).frame(
                maxWidth: .infinity
              ).padding(.top, 4)
            }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 23))
          }
          if let message = purchases.purchaseMessage {
            Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
          }
        }.padding(20).padding(.bottom, 24)
      }
    }.onAppear { purchases.refresh() }
  }

  private func feature(_ symbol: String, _ title: String, _ detail: String, tint: Color)
    -> some View
  {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.subheadline.bold())
        Text(detail).font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
}

extension SafetyCategory {
  fileprivate var shortName: String {
    switch self {
    case .routeDisruption: "Roads"
    case .unsafeBehaviour: "Safety"
    case .crimeReported: "Crime"
    case .neighbourhood: "Break-ins"
    }
  }
  fileprivate var tint: Color {
    switch self {
    case .routeDisruption: .coral
    case .unsafeBehaviour: .amber
    case .crimeReported: .blue
    case .neighbourhood: .purple
    }
  }
}
extension Color {
  static let weywellSky = Color(red: 0.75, green: 0.90, blue: 0.98)
  static let weywellMist = Color(red: 0.94, green: 0.98, blue: 1)
  static let weywellInk = Color(red: 0.08, green: 0.22, blue: 0.36)
  static let coral = Color(red: 0.94, green: 0.36, blue: 0.33)
  static let amber = Color(red: 0.95, green: 0.65, blue: 0.18)
  static let purple = Color(red: 0.53, green: 0.34, blue: 0.91)
  static let weywellMint = Color(red: 0.20, green: 0.70, blue: 0.58)
}
