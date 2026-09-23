import SwiftUI
import UIKit

struct PlusView: View {
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
  var shortName: String {
    switch self {
    case .routeDisruption: "Roads"
    case .unsafeBehaviour: "Safety"
    case .crimeReported: "Crime"
    case .neighbourhood: "Break-ins"
    }
  }
  var tint: Color {
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
