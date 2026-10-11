import Foundation

/// Lifecycle of one request. The transitions are the only places the agent
/// touches the filesystem for that request, so every path through the machine
/// either produces a reply or leaves a logged rejection.
public enum RequestState: Equatable {
    case pending(Request)
    case validated(Request, WhitelistedCommand)
    case running(Request, WhitelistedCommand)
    case replied(Request, Reply)
    case rejected(Request?, Reason)

    public enum Reason: Equatable {
        case unknownVerb(String)
        case parseFailed(Request.ParseError)
        case executionFailed(String)
        case stale
        case cancelled
    }
}

/// Pure request processor: no I/O. A thin runner around this can watch the
/// spool, invoke Process for `.running`, and write the reply.
public struct RequestProcessor {
    public var registry: CommandRegistry
    /// Clock injection so tests can freeze time for report filenames.
    public var now: () -> Date
    public var uuid: () -> String

    public init(registry: CommandRegistry, now: @escaping () -> Date = Date.init,
                uuid: @escaping () -> String = { UUID().uuidString }) {
        self.registry = registry; self.now = now; self.uuid = uuid
    }

    public func begin(filename: String, contents: String) -> RequestState {
        do {
            let req = try Request.parse(filename: filename, contents: contents)
            return .pending(req)
        } catch let e as Request.ParseError {
            return .rejected(nil, .parseFailed(e))
        } catch {
            return .rejected(nil, .parseFailed(.emptyFile))
        }
    }

    public func validate(_ state: RequestState) -> RequestState {
        guard case .pending(let req) = state else { return state }
        guard let cmd = registry.lookup(req.verb) else {
            return .rejected(req, .unknownVerb(req.verb))
        }
        return .validated(req, cmd)
    }

    public func markRunning(_ state: RequestState) -> RequestState {
        guard case .validated(let req, let cmd) = state else { return state }
        return .running(req, cmd)
    }

    /// Build the reply after an execution result. Report paths are constructed
    /// here from the command's fixed directory and a timestamp; the request
    /// never contributes a path component.
    public func finish(_ state: RequestState, exitCode: Int32, stdout: Data, stderr: Data) -> RequestState {
        guard case .running(let req, let cmd) = state else { return state }
        if exitCode != 0 {
            let msg = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .rejected(req, .executionFailed(msg?.isEmpty == false ? msg! : "exit \(exitCode)"))
        }
        switch cmd.output {
        case .ok:
            return .replied(req, Reply(id: req.id, kind: .ok))
        case .report(let dir, let prefix):
            let stamp = Self.timestamp(now())
            let name = "\(prefix)-\(stamp).txt"
            // Defense in depth: prefix and directory were set by the developer
            // when building the registry, never by a request.
            let path = (dir as NSString).appendingPathComponent(name)
            return .replied(req, Reply(id: req.id, kind: .path(path)))
        }
    }

    /// Convenience: parse + validate in one step.
    public func accept(filename: String, contents: String) -> RequestState {
        validate(begin(filename: filename, contents: contents))
    }

    static func timestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: d)
    }
}

/// Sweep `done-*` replies older than `maxAge`. The skill uses `find -mmin +5`.
public struct StaleReplyCleaner {
    public var maxAge: TimeInterval
    public var now: () -> Date

    public init(maxAge: TimeInterval = 5 * 60, now: @escaping () -> Date = Date.init) {
        self.maxAge = maxAge; self.now = now
    }

    /// Returns the filenames that should be deleted.
    public func expired(entries: [(name: String, mtime: Date)]) -> [String] {
        let cutoff = now().addingTimeInterval(-maxAge)
        return entries.compactMap { e in
            guard e.name.hasPrefix("done-"), e.mtime < cutoff else { return nil }
            return e.name
        }
    }
}
