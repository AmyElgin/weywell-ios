import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct ReportSheet: View {
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
