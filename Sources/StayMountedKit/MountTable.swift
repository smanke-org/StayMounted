import Foundation

/// An SMB share mounted on this Mac right now.
public struct MountedShare: Hashable, Sendable, Identifiable {
    public let source: ShareURL
    public let mountPoint: String

    public var id: String { mountPoint }
    public var key: ShareKey { source.key }

    public init(source: ShareURL, mountPoint: String) {
        self.source = source
        self.mountPoint = mountPoint
    }
}

/// Reads the kernel's mount table.
///
/// `getmntinfo` is a local system call: it never touches the share itself, so it cannot
/// hang on a dead server or raise the "would like to access files on a network volume"
/// prompt that probing a mount point does.
public enum MountTable {
    public static func smbMounts() -> [MountedShare] {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else { return [] }

        var result: [MountedShare] = []
        for index in 0..<Int(count) {
            var entry = buffer[index]
            let fsType = string(from: &entry.f_fstypename)
            let from = string(from: &entry.f_mntfromname)
            let on = string(from: &entry.f_mntonname)
            if let share = include(fsType: fsType, from: from, on: on, flags: entry.f_flags) {
                result.append(share)
            }
        }
        return result
    }

    /// The filtering rules, separated so they can be tested without a real mount table.
    ///
    /// Time Machine mounts its own private copy of a backup share under
    /// `/Volumes/.timemachine` with `nobrowse`; it is not something the user mounted and
    /// must never be offered or counted as the user's share being present.
    public static func include(fsType: String, from: String, on: String, flags: UInt32) -> MountedShare? {
        guard fsType == "smbfs" else { return nil }
        guard flags & UInt32(MNT_DONTBROWSE) == 0 else { return nil }
        guard !on.hasPrefix("/Volumes/.") else { return nil }
        guard let source = ShareURL(mountedFrom: from) else { return nil }
        return MountedShare(source: source, mountPoint: on)
    }

    private static func string<T>(from tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
