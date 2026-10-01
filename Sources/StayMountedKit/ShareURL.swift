import Foundation

/// Identifies an SMB share independent of how its address was spelled.
///
/// The same share shows up in several forms: Finder mounts `smb://MediaNAS.local/Media`
/// as `//user@MediaNAS._smb._tcp.local/Media` in the mount table, a user may type
/// `\\MediaNAS\Media`, and share names are percent-encoded in URLs but not on disk.
/// Matching compares a normalized host and share name, both case-insensitively, the way
/// SMB itself treats them.
public struct ShareKey: Hashable, Sendable, CustomStringConvertible {
    public let host: String
    public let share: String

    public init(host: String, share: String) {
        self.host = Self.normalizeHost(host)
        self.share = share.lowercased()
    }

    public var description: String { "\(host)/\(share)" }

    /// `MediaNAS._smb._tcp.local`, `MediaNAS.local` and `medianas` are one machine:
    /// a Bonjour service name, its mDNS host name, and the bare name a user types.
    /// Fully qualified names outside `.local` and IP addresses are left alone.
    static func normalizeHost(_ host: String) -> String {
        var name = host.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        for suffix in ["._smb._tcp.local", ".local"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
            break
        }
        return name
    }
}

/// A parsed SMB share address.
public struct ShareURL: Hashable, Sendable {
    /// Host as written, minus any user name, e.g. `MediaNAS.local` or `MediaNAS._smb._tcp.local`.
    public let host: String
    /// Share name, decoded, in its original case.
    public let share: String
    /// Any path below the share, decoded, without a leading slash. Usually empty.
    public let subpath: String
    /// User name from the address, if one was given.
    public let user: String?

    public var key: ShareKey { ShareKey(host: host, share: share) }

    /// The canonical `smb://` URL to hand to NetFS. The user name is kept, because NetAuth
    /// looks up the Keychain item by account as well as server.
    public var url: URL {
        var components = URLComponents()
        components.scheme = "smb"
        components.host = host
        components.user = user
        components.path = "/" + ([share] + (subpath.isEmpty ? [] : [subpath])).joined(separator: "/")
        return components.url!
    }

    /// The address as people write it, without the user name.
    public var displayString: String {
        "smb://\(host)/\(share)" + (subpath.isEmpty ? "" : "/\(subpath)")
    }

    /// The host as it reads in a menu: the Bonjour suffix is noise to people.
    public var displayHost: String {
        let lower = host.lowercased()
        if lower.hasSuffix("._smb._tcp.local") {
            return String(host.dropLast("._smb._tcp.local".count))
        }
        return host
    }

    public init(host: String, share: String, subpath: String = "", user: String? = nil) {
        self.host = host
        self.share = share
        self.subpath = subpath
        self.user = user
    }

    /// Accepts what people actually type or paste: `smb://host/share`, `cifs://host/share`,
    /// `//host/share`, `\\host\share`, `host/share`, with or without `user@`.
    /// Returns nil for anything without both a host and a share name.
    public init?(parsing input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        text = text.replacingOccurrences(of: "\\", with: "/")
        let lower = text.lowercased()
        if lower.hasPrefix("smb://") {
            text.removeFirst("smb://".count)
        } else if lower.hasPrefix("cifs://") {
            text.removeFirst("cifs://".count)
        } else if lower.contains("://") {
            return nil // afp://, nfs://, https:// — not ours
        } else {
            while text.hasPrefix("/") { text.removeFirst() }
        }

        // Split authority from path on the first slash, so a user name containing an
        // encoded slash cannot be mistaken for the path.
        guard let slash = text.firstIndex(of: "/") else { return nil }
        var authority = String(text[..<slash])
        let path = text[text.index(after: slash)...]
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }

        var user: String?
        if let at = authority.lastIndex(of: "@") {
            let rawUser = String(authority[..<at])
            // "user:password@" — drop the password; it belongs in the Keychain, not here.
            let name = rawUser.split(separator: ":", maxSplits: 1).first.map(String.init) ?? rawUser
            user = name.removingPercentEncoding ?? name
            if user?.isEmpty == true { user = nil }
            authority = String(authority[authority.index(after: at)...])
        }
        // A port is irrelevant to identity and NetFS takes the default.
        if let colon = authority.lastIndex(of: ":"), !authority.hasPrefix("[") {
            authority = String(authority[..<colon])
        }
        authority = authority.removingPercentEncoding ?? authority

        guard !authority.isEmpty, let share = path.first, !share.isEmpty else { return nil }
        self.init(host: authority, share: share, subpath: path.dropFirst().joined(separator: "/"), user: user)
    }

    /// Parses the `f_mntfromname` the kernel records for an smbfs mount,
    /// e.g. `//smanke@MediaNAS._smb._tcp.local/Media_Files_NAS`.
    public init?(mountedFrom name: String) {
        self.init(parsing: name)
    }
}
