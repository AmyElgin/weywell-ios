import SwiftUI
import UIKit
import UserNotifications

final class PushAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Task { @MainActor in PushSync.shared.receivedDeviceToken(deviceToken) }
  }

  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    Task { @MainActor in PushSync.shared.registrationFailed(error) }
  }
}

@main
struct WeywellApp: App {
  @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
  @AppStorage("weywell.onboardingComplete") private var onboardingComplete = false
  @StateObject private var purchases = PurchaseManager.shared
  @StateObject private var notices = NoticeStore()
  @StateObject private var monitoring = MonitorManager.shared
  @StateObject private var profile = ProfileStore.shared
  @State private var recoveryAccessToken: String?
  @State private var isShowingPasswordReset = false

  init() {
    PurchaseManager.shared.configure()
    UNUserNotificationCenter.current().delegate = WeywellNotificationDelegate.shared
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if onboardingComplete {
          ContentView()
        } else {
          OnboardingView { onboardingComplete = true }
        }
      }
      .environmentObject(purchases)
      .environmentObject(notices)
      .environmentObject(monitoring)
      .environmentObject(profile)
      .task {
        monitoring.refreshPermission()
        await PushSync.shared.sync()
      }
      .onChange(of: purchases.isPro) { _, _ in Task { await PushSync.shared.sync() } }
      .onOpenURL { url in
        guard let token = recoveryToken(from: url) else { return }
        recoveryAccessToken = token
        isShowingPasswordReset = true
      }
      .sheet(isPresented: $isShowingPasswordReset, onDismiss: { recoveryAccessToken = nil }) {
        if let recoveryAccessToken {
          PasswordResetView(accessToken: recoveryAccessToken) {}
        }
      }
    }
  }

  private func recoveryToken(from url: URL) -> String? {
    guard url.scheme == "weywell" else { return nil }
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let fragmentItems =
      URLComponents(string: "https://callback.invalid/?\(url.fragment ?? "")")?.queryItems ?? []
    let items = queryItems + fragmentItems
    guard items.first(where: { $0.name == "type" })?.value == "recovery" else { return nil }
    return items.first(where: { $0.name == "access_token" })?.value
  }
}

private struct OnboardingView: View {
  let complete: () -> Void
  @State private var page = 0

  private let steps: [(icon: String, eyebrow: String, title: String, detail: String)] = [
    (
      "map.fill", "KNOW YOUR AREA", "A clearer view of what’s nearby",
      "Explore community safety notices around your location or a saved home address. Zoom in, choose a radius, and check what is current."
    ),
    (
      "point.topleft.down.curvedto.point.bottomright.up", "BEFORE YOU GO", "Check the road ahead",
      "Find a destination and see a real driving route with relevant notices along it. Reports are context, not a guarantee of safety."
    ),
    (
      "megaphone.fill", "HELP EACH OTHER", "Share useful, careful updates",
      "Report road disruptions, unsafe behaviour, crime or neighbourhood context. New reports are reviewed and short lived; avoid names and private details."
    ),
  ]
  private let accents: [Color] = [.blue, .coral, .purple]

  var body: some View {
    ZStack {
      Color.weywellSky.ignoresSafeArea()
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("WEYWELL").font(.system(size: 25, weight: .black, design: .rounded)).tracking(-0.7)
          Spacer()
          if page < steps.count - 1 {
            Button("Skip") { complete() }.font(.subheadline.bold()).foregroundStyle(.secondary)
          }
        }
        .padding(.top, 18)

        Spacer(minLength: 24)
        ZStack {
          RoundedRectangle(cornerRadius: 34).fill(.white).frame(height: 290)
          Circle().fill(accents[page].opacity(0.10)).frame(width: 225, height: 225)
          Circle().stroke(accents[page].opacity(0.30), lineWidth: 2).frame(width: 215, height: 215)
          Circle().stroke(accents[page].opacity(0.20), lineWidth: 2).frame(width: 145, height: 145)
          Image(systemName: steps[page].icon).font(.system(size: 65, weight: .medium))
            .foregroundStyle(accents[page])
            .frame(width: 126, height: 126).background(
              .white, in: RoundedRectangle(cornerRadius: 31)
            ).shadow(color: accents[page].opacity(0.18), radius: 20, y: 8)
        }
        .accessibilityHidden(true)
        Spacer(minLength: 28)

        Text(steps[page].eyebrow).font(.caption.bold()).tracking(1.6).foregroundStyle(accents[page])
        Text(steps[page].title).font(.system(size: 34, weight: .black, design: .rounded)).fixedSize(
          horizontal: false, vertical: true
        ).padding(.top, 8)
        Text(steps[page].detail).font(.body).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true
        ).padding(.top, 13)

        HStack(spacing: 7) {
          ForEach(steps.indices, id: \.self) { index in
            Capsule().fill(index == page ? accents[page] : accents[page].opacity(0.2)).frame(
              width: index == page ? 25 : 8, height: 8)
          }
        }.padding(.top, 27)

        Button {
          if page == steps.count - 1 {
            complete()
          } else {
            withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
          }
        } label: {
          Text(page == steps.count - 1 ? "Explore Weywell" : "Continue").font(.headline).frame(
            maxWidth: .infinity
          ).padding(.vertical, 17).background(accents[page], in: RoundedRectangle(cornerRadius: 17))
        }.foregroundStyle(.white).padding(.top, 23)
        Text("Free safety map, reports and route checks. Extra controls are optional.").font(
          .caption
        ).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
          .padding(.top, 12)
      }.padding(.horizontal, 24).padding(.bottom, 20)
    }
  }
}
