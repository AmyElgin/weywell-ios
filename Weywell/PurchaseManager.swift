import Foundation
import RevenueCat

@MainActor
final class PurchaseManager: NSObject, ObservableObject {
  static let shared = PurchaseManager()
  @Published private(set) var isPro = false
  @Published private(set) var offering: Offering?
  @Published var purchaseMessage: String?
  var isTestStore: Bool {
    (Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicSDKKey") as? String)?.hasPrefix(
      "test_") == true
  }

  private override init() { super.init() }

  func configure() {
    let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicSDKKey") as? String ?? ""
    guard apiKey.hasPrefix("appl_") || apiKey.hasPrefix("test_") else {
      purchaseMessage = "Add your RevenueCat public iOS SDK key to enable Weywell Plus."
      return
    }
    Purchases.logLevel = .debug
    Purchases.configure(withAPIKey: apiKey)
    refresh()
  }

  func refresh() {
    Purchases.shared.getCustomerInfo { [weak self] info, _ in
      DispatchQueue.main.async {
        self?.isPro = info?.entitlements["weywell_plus"]?.isActive == true
      }
    }
    Purchases.shared.getOfferings { [weak self] offerings, error in
      DispatchQueue.main.async {
        self?.offering = offerings?.current
        if let error {
          self?.purchaseMessage = "Couldn’t load Plus options: \(error.localizedDescription)"
        }
      }
    }
  }

  func purchase() {
    purchaseMessage = nil
    guard let package = offering?.availablePackages.first else {
      purchaseMessage =
        "No purchase option is available yet. Finish the RevenueCat dashboard setup first."
      return
    }
    Purchases.shared.purchase(package: package) { [weak self] _, info, error, cancelled in
      DispatchQueue.main.async {
        guard !cancelled else { return }
        if let error {
          self?.purchaseMessage = error.localizedDescription
          return
        }
        self?.isPro = info?.entitlements["weywell_plus"]?.isActive == true
        self?.purchaseMessage =
          self?.isPro == true ? "Weywell Plus is active." : "Purchase completed."
      }
    }
  }

  func restore() {
    purchaseMessage = nil
    Purchases.shared.restorePurchases { [weak self] info, error in
      DispatchQueue.main.async {
        if let error {
          self?.purchaseMessage = error.localizedDescription
          return
        }
        self?.isPro = info?.entitlements["weywell_plus"]?.isActive == true
        self?.purchaseMessage =
          self?.isPro == true ? "Purchases restored." : "No active Weywell Plus purchase found."
      }
    }
  }
}
