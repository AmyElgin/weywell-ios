import MapKit
import SwiftUI
import UIKit

struct AlertCentre: View {
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

struct ProfileView: View {
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
