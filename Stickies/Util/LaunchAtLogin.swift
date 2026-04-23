import Foundation
import ServiceManagement

enum LaunchAtLogin {

    private static let userDefaultsKey = "launchAtLoginUserPreference"

    /// User-visible preference (checkbox state). Source of truth.
    static var userPreference: Bool {
        get {
            if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
                return true // default ON for first launch
            }
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            reconcile()
        }
    }

    /// Brings SMAppService state in line with `userPreference`. Safe to call on launch.
    static func reconcile() {
        let want = userPreference
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled where !want:
                try service.unregister()
            case .notRegistered where want:
                try service.register()
            default:
                if want && service.status != .enabled { try service.register() }
                if !want && service.status == .enabled { try service.unregister() }
            }
        } catch {
            NSLog("LaunchAtLogin reconcile failed: \(error)")
        }
    }
}
