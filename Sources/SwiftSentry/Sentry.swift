import Foundation
import AsyncHTTPClient
import NIO

public struct Sentry {
    enum SwiftSentryError: Error {
        //case CantEncodeEvent
        //case CantCreateRequest
        case NoResponseBody(status: UInt)
        case InvalidArgumentException(_ msg: String)
    }

    internal static let VERSION = "SentrySwift/0.1.0"

    private let dsn: Dsn
    private var httpClient: HTTPClient
    internal var servername: String?
    internal var release: String?
    internal var environment: String?

    public init(
        dsn: String,
        httpClient: HTTPClient = HTTPClient(eventLoopGroupProvider: .createNew),
        servername: String? = getHostname(),
        release: String? = nil,
        environment: String? = nil
    ) throws {
        self.dsn = try Dsn(fromString: dsn)
        self.httpClient = httpClient
        self.servername = servername
        self.release = release
        self.environment = environment
    }

    public func shutdown() throws {
        try httpClient.syncShutdown()
    }
    
    /// Get hostname from linux C function `gethostname`. The integrated function `ProcessInfo.processInfo.hostName` does not seem to work reliable on linux
    static public func getHostname() -> String {
        var data = [CChar](repeating: 0, count: 265)
        let string: String? = data.withUnsafeMutableBufferPointer({
            guard let ptr = $0.baseAddress else {
                return nil
            }
            gethostname(ptr, 256)
            return String(cString: ptr, encoding: .utf8)
        })
        return string ?? ""
    }

    @discardableResult
    public func capture(error: Error, eventLoop: EventLoop? = nil) -> EventLoopFuture<UUID> {
        let edb = ExceptionDataBag(
            type: "\(error.self)",
            value: error.localizedDescription,
            stacktrace: nil
        )

        let exceptions = Exceptions(values: [edb])

        let event = Event(
            event_id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            level: .error,
            logger: nil,
            transaction: nil,
            server_name: self.servername,
            release: self.release,
            tags: nil,
            environment: self.environment,
            message: .raw(message: "\(error.localizedDescription)"),
            exception: exceptions,
            breadcrumbs: nil,
            user: nil
        )

        return send(event: event, eventLoop: eventLoop)
    }
    
    /// Log a message to sentry
    @discardableResult
    public func capture(
        message: String,
        level: Level,
        logger: String? = nil,
        transaction: String? = nil,
        tags: [String: String]? = nil,
        file: String? = #file,
        filePath: String? = #filePath,
        function: String? = #function,
        line: Int? = #line,
        column: Int? = #column,
        eventLoop: EventLoop? = nil) -> EventLoopFuture<UUID> {
        
        let frame = Frame(filename: file, function: function, raw_function: nil, lineno: line, colno: column, abs_path: filePath, instruction_addr: nil)
        let stacktrace = Stacktrace(frames: [frame])

        let event = Event(
            event_id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            level: level,
            logger: logger,
            transaction: transaction,
            server_name: servername,
            release: release,
            tags: tags,
            environment: environment,
            message: .raw(message: message),
            exception: Exceptions(values: [ExceptionDataBag(type: level.rawValue, value: nil, stacktrace: stacktrace)]),
            breadcrumbs: nil,
            user: nil
        )

        return send(event: event, eventLoop: eventLoop)
    }

    @discardableResult
    public func uploadStackTrace(path: String, eventLoop: EventLoop? = nil) throws -> EventLoopFuture<[UUID]> {
        let eventLoop = eventLoop ?? httpClient.eventLoopGroup.next()

        // read all lines from the error log
        guard let content = try? String(contentsOfFile: path) else {
            return eventLoop.makeSucceededFuture([UUID]())
        }

        // empty the error log (we don't want to send events twice)
        try "".write(toFile: path, atomically: true, encoding: .utf8)
        
        let events = FatalError.parseStacktrace(content).map {
            $0.getEvent(servername: servername, release: release, environment: environment)
        }

        return EventLoopFuture.whenAllSucceed(events.map ({ send(event: $0) }), on: eventLoop)
    }

    @discardableResult
    internal func send(event: Event, eventLoop: EventLoop? = nil) -> EventLoopFuture<UUID> {
        let eventLoop = eventLoop ?? httpClient.eventLoopGroup.next()

        do {
            let data = try JSONEncoder().encode(event)
            var request = try HTTPClient.Request(url: dsn.getStoreApiEndpointUrl(), method: .POST)
            
            request.headers.replaceOrAdd(name: "Content-Type", value: "application/json")
            request.headers.replaceOrAdd(name: "User-Agent", value: Sentry.VERSION)
            request.headers.replaceOrAdd(name: "X-Sentry-Auth", value: self.dsn.getAuthHeader())
            request.body = HTTPClient.Body.data(data)

            return httpClient.execute(request: request, eventLoop: .delegate(on: eventLoop)).flatMapThrowing({ resp -> UUID in
                guard var body = resp.body, let id = body.getUUIDHexadecimalEncoded() else {
                    throw SwiftSentryError.NoResponseBody(status: resp.status.code)
                }
                return id
            })
        } catch {
            return eventLoop.makeFailedFuture(error)
        }
    }
}
