import Foundation

/// A share the user asked to keep mounted.
public struct WatchedShare: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    /// The address as given, including any user name, so NetAuth finds the right
    /// Keychain item.
    public var address: String
    /// Not remounted while paused. Set by "Keep ejected", or from the menu.
    public var paused = false
    /// Opened, in this order, every time the share mounts.
    public var apps: [LaunchItem] = []
    /// Seconds to wait after the share mounts before opening `apps`.
    public var launchDelay = 0

    public var share: ShareURL? { ShareURL(parsing: address) }
    public var displayName: String { share?.share ?? address }

    public init(id: UUID = UUID(), address: String, paused: Bool = false,
                apps: [LaunchItem] = [], launchDelay: Int = 0) {
        self.id = id
        self.address = address
        self.paused = paused
        self.apps = apps
        self.launchDelay = launchDelay
    }

    private enum CodingKeys: String, CodingKey {
        case id, address, paused, apps, launchDelay
    }

    /// Written by hand so that a key a later version added is optional. The synthesized
    /// decoder throws on a missing key, and AppSettings falls back to an empty list when
    /// decoding fails — upgrading from 1.0.9, which saved no `apps`, would have silently
    /// forgotten every share.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        address = try container.decode(String.self, forKey: .address)
        paused = try container.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        apps = try container.decodeIfPresent([LaunchItem].self, forKey: .apps) ?? []
        launchDelay = try container.decodeIfPresent(Int.self, forKey: .launchDelay) ?? 0
    }
}

/// An app to open when a share mounts.
public struct LaunchItem: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    /// Preferred for finding the app, so it is still found after being moved or updated.
    public var bundleIdentifier: String?
    /// Where the app was when it was added; used when there is no bundle identifier or
    /// LaunchServices no longer knows it.
    public var path: String
    public var name: String
    /// Opened hidden, without coming to the front.
    public var hidden = false

    public init(id: UUID = UUID(), bundleIdentifier: String?, path: String, name: String, hidden: Bool = false) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.name = name
        self.hidden = hidden
    }

    /// Reads the identifier and display name from an app bundle.
    public init?(appAt url: URL) {
        guard let bundle = Bundle(url: url), url.pathExtension == "app" else { return nil }
        let info = bundle.localizedInfoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        self.init(bundleIdentifier: bundle.bundleIdentifier, path: url.path, name: name)
    }

    private enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, path, name, hidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
}
