import Foundation

public let daemonService = "com.scotta.daemon"
public let changedNotification = "com.scotta.changed"
/// Only binaries signed by the same team as the daemon may talk to it.
public func clientRequirement(team: String) -> String {
    #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
}

@objc public protocol ScottaXPC {
    func status(reply: @escaping (Data) -> Void)
    /// Replies with an error message, or nil on success.
    func send(_ command: Data, reply: @escaping (String?) -> Void)
}

/// Thin synchronous-or-async client shared by the app and the CLI.
public final class DaemonClient {
    private let conn: NSXPCConnection

    public init() {
        conn = NSXPCConnection(machServiceName: daemonService, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: ScottaXPC.self)
        conn.resume()
    }

    private func proxy(_ fail: @escaping (String) -> Void) -> ScottaXPC? {
        conn.remoteObjectProxyWithErrorHandler { fail("daemon unreachable: \($0.localizedDescription)") } as? ScottaXPC
    }

    public func status(_ done: @escaping (Result<Status, Error>) -> Void) {
        proxy { done(.failure(ScottaError($0))) }?.status { data in
            done(Result { try JSONDecoder.scotta.decode(Status.self, from: data) })
        }
    }

    public func send(_ c: Command, _ done: @escaping (String?) -> Void) {
        guard let data = try? JSONEncoder.scotta.encode(c) else { return done("encode failed") }
        proxy(done)?.send(data, reply: done)
    }
}

public struct ScottaError: LocalizedError {
    public let errorDescription: String?
    public init(_ m: String) { errorDescription = m }
}
