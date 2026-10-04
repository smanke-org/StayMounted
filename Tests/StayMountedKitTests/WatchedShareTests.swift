import Foundation
import Testing
@testable import StayMountedKit

struct WatchedShareTests {
    /// What 1.0.9 saved: no `apps` or `launchDelay`. Failing to decode this would make
    /// AppSettings start with no shares at all after the upgrade.
    @Test func decodesPrefsSavedBeforeAppLaunching() throws {
        let json = """
        [{"id":"6F1C2E2A-8B0D-4C1E-9D52-0A6A5E0B1C11","address":"smb://nas.local/Media","paused":true},
         {"id":"0B1C2D3E-4F50-6172-8394-A5B6C7D8E9F0","address":"smb://nas.local/home","paused":false}]
        """
        let shares = try JSONDecoder().decode([WatchedShare].self, from: Data(json.utf8))
        #expect(shares.count == 2)
        #expect(shares[0].paused)
        #expect(shares[0].displayName == "Media")
        #expect(shares[0].apps.isEmpty)
        #expect(shares[0].launchDelay == 0)
        #expect(shares[0].id == UUID(uuidString: "6F1C2E2A-8B0D-4C1E-9D52-0A6A5E0B1C11"))
    }

    @Test func roundTripsAppsAndDelay() throws {
        let share = WatchedShare(
            address: "smb://nas.local/Media",
            apps: [
                LaunchItem(bundleIdentifier: "com.example.Player", path: "/Applications/Player.app", name: "Player", hidden: true),
                LaunchItem(bundleIdentifier: nil, path: "/Applications/Tool.app", name: "Tool"),
            ],
            launchDelay: 5
        )
        let decoded = try JSONDecoder().decode(WatchedShare.self, from: JSONEncoder().encode(share))
        #expect(decoded == share)
    }

    @Test func readsAppBundle() throws {
        let item = try #require(LaunchItem(appAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app")))
        #expect(item.bundleIdentifier == "com.apple.TextEdit")
        #expect(item.name == "TextEdit")
        #expect(!item.hidden)
    }

    @Test func rejectsNonApp() {
        #expect(LaunchItem(appAt: URL(fileURLWithPath: "/System/Library")) == nil)
    }
}
