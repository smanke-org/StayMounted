import Foundation
import Observation
import StayMountedKit

/// A share the user asked to keep mounted.
struct WatchedShare: Codable, Identifiable, Hashable {
    var id = UUID()
    /// The address as given, including any user name, so NetAuth finds the right
    /// Keychain item.
    var address: String
    /// Not remounted while paused. Set by "Keep ejected", or from the menu.
    var paused = false

    var share: ShareURL? { ShareURL(parsing: address) }
    var displayName: String { share?.share ?? address }
}

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    var shares: [WatchedShare] { didSet { saveShares() } }

    /// Stops all remounting without forgetting anything.
    var pausedAll: Bool { didSet { defaults.set(pausedAll, forKey: "pausedAll") } }

    /// Ask before remounting a share that was ejected while the network was fine — most
    /// likely by hand. Off remounts at once, as if it had dropped.
    var confirmAfterEject: Bool { didSet { defaults.set(confirmAfterEject, forKey: "confirmAfterEject") } }

    /// Look for a newer release shortly after launch. Silent unless there is something to
    /// install. Unused in the App Store build, which the store updates.
    var checkForUpdatesAtLaunch: Bool { didSet { defaults.set(checkForUpdatesAtLaunch, forKey: "checkForUpdatesAtLaunch") } }

    /// A version the user chose to skip; the launch check stays quiet about it.
    var skippedUpdateVersion: String? { didSet { defaults.set(skippedUpdateVersion, forKey: "skippedUpdateVersion") } }

    /// Launch at login is switched on once, the first time the app runs from
    /// /Applications — keeping shares mounted across restarts is the point of the app.
    /// After that it is the user's setting, and turning it off sticks.
    var didOfferLaunchAtLogin: Bool { didSet { defaults.set(didOfferLaunchAtLogin, forKey: "didOfferLaunchAtLogin") } }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "pausedAll": false,
            "confirmAfterEject": true,
            "checkForUpdatesAtLaunch": true,
            "didOfferLaunchAtLogin": false,
        ])
        if let data = defaults.data(forKey: "shares"),
           let decoded = try? JSONDecoder().decode([WatchedShare].self, from: data) {
            shares = decoded
        } else {
            shares = []
        }
        pausedAll = defaults.bool(forKey: "pausedAll")
        confirmAfterEject = defaults.bool(forKey: "confirmAfterEject")
        checkForUpdatesAtLaunch = defaults.bool(forKey: "checkForUpdatesAtLaunch")
        skippedUpdateVersion = defaults.string(forKey: "skippedUpdateVersion")
        didOfferLaunchAtLogin = defaults.bool(forKey: "didOfferLaunchAtLogin")
    }

    private func saveShares() {
        if let data = try? JSONEncoder().encode(shares) {
            defaults.set(data, forKey: "shares")
        }
    }
}
