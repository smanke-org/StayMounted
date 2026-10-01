import Foundation
import NetFS

/// Why a mount attempt failed, in the terms the app acts on.
public enum MountFailure: Error, Equatable, Sendable {
    /// No usable password in the Keychain, or it was rejected. Retrying in the background
    /// cannot fix this; only the user can.
    case needsSignIn
    /// The user dismissed the sign-in dialog.
    case cancelled
    /// The server did not answer.
    case unreachable
    /// The server answered but has no share by that name, or refused it.
    case shareNotFound
    case other(code: Int32)

    public var message: String {
        switch self {
        case .needsSignIn: "Sign in needed"
        case .cancelled: "Sign-in cancelled"
        case .unreachable: "Server not responding"
        case .shareNotFound: "Share not found on the server"
        case .other(let code): "Mount failed (error \(code))"
        }
    }

    /// Maps NetFS's mix of errno values and NetAuth status codes.
    public init(status: Int32) {
        switch status {
        case EAUTH, EACCES, EPERM, ENETFSPWDNEEDSCHANGE, ENETFSPWDPOLICY, ENETFSACCOUNTRESTRICTED,
             ENETFSNOAUTHMECHSUPP:
            self = .needsSignIn
        case -128 /* userCanceledErr */, ECANCELED:
            self = .cancelled
        case ETIMEDOUT, EHOSTUNREACH, ENETUNREACH, ECONNREFUSED, EHOSTDOWN, ENETDOWN, ECONNRESET:
            self = .unreachable
        case ENOENT, ENETFSNOSHARESAVAIL:
            self = .shareNotFound
        default:
            self = .other(code: status)
        }
    }
}

/// Mounts SMB shares the way Finder does, through NetFS.
///
/// No user name or password is passed: NetAuth then uses the Keychain item Finder saved
/// when "Remember this password" was ticked. The mount goes in `/Volumes` under the
/// share's name, so it appears on the desktop exactly as a Finder mount would.
///
/// NetFS does the work in NetAuthAgent rather than in this process, which is why this
/// works unchanged inside the App Sandbox (verified with a sandboxed, Developer ID-signed
/// test bundle on 2026-10-01).
public enum Mounter {
    /// - Parameter interactive: false never shows any UI — a background attempt must not
    ///   put a dialog in front of someone. true lets NetAuth show its sign-in sheet, with
    ///   the "Remember this password in my keychain" box.
    /// - Returns: the mount point(s) on success.
    public static func mount(_ share: ShareURL, interactive: Bool) async -> Result<[String], MountFailure> {
        let openOptions = NSMutableDictionary()
        openOptions[kNAUIOptionKey as String] = interactive ? kNAUIOptionAllowUI : kNAUIOptionNoUI
        let mountOptions = NSMutableDictionary()

        let queue = DispatchQueue(label: "StayMounted.mount")
        let once = Once()

        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<[String], MountFailure>, Never>) in
            var requestID: AsyncRequestID?
            let started = NetFSMountURLAsync(
                share.url as CFURL, nil, nil, nil,
                openOptions, mountOptions, &requestID, queue
            ) { status, _, mountPoints in
                guard once.claim() else { return }
                let points = (mountPoints as? [String]) ?? []
                switch status {
                case 0:
                    continuation.resume(returning: .success(points))
                case EEXIST:
                    // Already mounted (by Finder, or by a previous attempt that raced this
                    // one). That is the outcome wanted.
                    continuation.resume(returning: .success(points))
                default:
                    continuation.resume(returning: .failure(MountFailure(status: status)))
                }
            }
            if started != 0, once.claim() {
                continuation.resume(returning: .failure(MountFailure(status: started)))
            }
        }
    }
}
