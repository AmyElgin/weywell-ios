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

struct Pin: View {
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
