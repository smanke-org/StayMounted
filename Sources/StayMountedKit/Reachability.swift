import Foundation
import Network

/// Answers "is this file server answering right now?" without ever blocking.
///
/// A TCP connection to the SMB port, through Network.framework, which resolves `.local`
/// names asynchronously. Plain `getaddrinfo` on a `.local` name was seen to block for as
/// long as a local-network permission prompt sat unanswered, which would freeze whatever
/// thread called it.
public enum Reachability {
    public enum Answer: Sendable, Equatable {
        case reachable
        /// With the reason, for the log.
        case unreachable(String)
        /// The app has not been allowed Local Network access (or the prompt is still up),
        /// so it cannot tell. Mounting itself is unaffected — NetFS runs in a system agent
        /// that this permission does not cover — so callers should go ahead and try.
        case blockedByPrivacy
    }

    /// DNS-SD's kDNSServiceErr_PolicyDenied: what a Local Network denial looks like.
    static let policyDenied: Int32 = -65570

    public static func check(host: String, timeout: Duration = .seconds(3)) async -> Answer {
        let endpoint = endpoint(for: host)
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "StayMounted.reachability")
        let once = Once()

        return await withCheckedContinuation { (continuation: CheckedContinuation<Answer, Never>) in
            @Sendable func finish(_ answer: Answer) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: answer)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.reachable)
                case .failed(let error), .waiting(let error):
                    // .waiting: no route, refused, or the name did not resolve.
                    // Network.framework would keep retrying; this wants an answer now.
                    finish(isPolicyDenial(error) ? .blockedByPrivacy : .unreachable("\(error)"))
                case .cancelled:
                    finish(.unreachable("cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout.timeInterval) { finish(.unreachable("no answer in \(timeout)")) }
        }
    }

    static func isPolicyDenial(_ error: NWError) -> Bool {
        if case .dns(let code) = error, code == policyDenied { return true }
        return false
    }

    /// Bonjour service names (`Name._smb._tcp.local`) are resolved as services, which is
    /// how Finder found them; everything else is a host on the SMB port.
    static func endpoint(for host: String) -> NWEndpoint {
        let lower = host.lowercased()
        if lower.hasSuffix("._smb._tcp.local") || lower.hasSuffix("._smb._tcp.local.") {
            let name = String(host.prefix(upTo: host.range(of: "._smb._tcp", options: .caseInsensitive)!.lowerBound))
            return .service(name: name, type: "_smb._tcp", domain: "local.", interface: nil)
        }
        return .hostPort(host: NWEndpoint.Host(host), port: 445)
    }
}

/// A one-shot latch, so a continuation is resumed exactly once whichever of the
/// state handler and the timeout gets there first.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
