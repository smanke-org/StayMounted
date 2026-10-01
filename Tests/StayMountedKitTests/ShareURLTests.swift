import Testing
import Darwin
@testable import StayMountedKit

struct ShareURLTests {
    @Test(arguments: [
        "smb://nas.local/Media",
        "SMB://NAS.local/media",
        "//user@nas._smb._tcp.local/Media",
        "\\\\nas\\Media",
        "nas/Media",
        "smb://user:secret@nas.local:445/Media",
        "cifs://nas/Media/",
    ])
    func sameShareMatches(_ input: String) throws {
        let parsed = try #require(ShareURL(parsing: input))
        #expect(parsed.key == ShareKey(host: "nas", share: "media"))
    }

    @Test func percentEncodedShareNameDecodes() throws {
        let parsed = try #require(ShareURL(parsing: "smb://nas.local/My%20Files"))
        #expect(parsed.share == "My Files")
        #expect(parsed.key == ShareKey(host: "nas.local", share: "my files"))
        #expect(parsed.url.absoluteString == "smb://nas.local/My%20Files")
    }

    @Test func passwordIsDropped() throws {
        let parsed = try #require(ShareURL(parsing: "smb://alice:hunter2@nas.local/Media"))
        #expect(parsed.user == "alice")
        #expect(!parsed.url.absoluteString.contains("hunter2"))
    }

    @Test func distinctHostsDoNotMatch() throws {
        let a = try #require(ShareURL(parsing: "smb://nas.example.com/Media"))
        let b = try #require(ShareURL(parsing: "smb://nas.local/Media"))
        #expect(a.key != b.key)
    }

    @Test func ipAddressKept() throws {
        let parsed = try #require(ShareURL(parsing: "smb://192.168.1.20/Media"))
        #expect(parsed.key.host == "192.168.1.20")
    }

    @Test(arguments: ["", "nas", "smb://nas", "smb://nas/", "afp://nas/Media", "https://nas/Media"])
    func rejectsIncomplete(_ input: String) {
        #expect(ShareURL(parsing: input) == nil)
    }

    @Test func displayHostDropsBonjourSuffix() throws {
        let parsed = try #require(ShareURL(mountedFrom: "//user@NAS._smb._tcp.local/Media"))
        #expect(parsed.displayHost == "NAS")
        #expect(parsed.user == "user")
    }
}

struct MountTableTests {
    @Test func includesUserSMBMount() throws {
        let share = try #require(MountTable.include(
            fsType: "smbfs", from: "//user@NAS._smb._tcp.local/Media", on: "/Volumes/Media", flags: 0))
        #expect(share.key == ShareKey(host: "nas", share: "media"))
    }

    @Test func skipsTimeMachineCopy() {
        let share = MountTable.include(
            fsType: "smbfs", from: "//user@NAS._smb._tcp.local/Media",
            on: "/Volumes/.timemachine/NAS._smb._tcp.local/7FA0/Media", flags: UInt32(MNT_DONTBROWSE))
        #expect(share == nil)
        // Even without the flag, a hidden /Volumes folder is never the user's mount.
        #expect(MountTable.include(
            fsType: "smbfs", from: "//NAS/Media", on: "/Volumes/.timemachine/x/Media", flags: 0) == nil)
    }

    @Test func skipsOtherFilesystems() {
        #expect(MountTable.include(fsType: "afpfs", from: "//NAS/Media", on: "/Volumes/Media", flags: 0) == nil)
        #expect(MountTable.include(fsType: "apfs", from: "/dev/disk3s1", on: "/", flags: 0) == nil)
    }

    @Test func liveTableParses() {
        // Whatever is mounted on the machine running the tests must at least parse.
        for share in MountTable.smbMounts() {
            #expect(!share.source.share.isEmpty)
            #expect(share.mountPoint.hasPrefix("/"))
        }
    }
}
