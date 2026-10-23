#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif
public import Logging

public struct EventId: RawRepresentable<UUID>, Codable, Sendable, Equatable {
    public var rawValue: UUID
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let id = try UUID(fromHexadecimalEncodedString: container.decode(String.self)) else {
            throw DecodingError.typeMismatch(EventId.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected UUID in hexadecimal format"))
        }
        self.rawValue = id
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue.hexadecimalEncoded)
    }
}

/// docs at https://develop.sentry.dev/sdk/event-payloads/
public struct Event: Encodable, Sendable {
    public init(
        event_id: UUID = .init(),
        timestamp: Double = Date().timeIntervalSince1970,
        platform: String = "other",
        level: Level? = nil,
        logger: String? = nil,
        transaction: String? = nil,
        server_name: String? = nil,
        release: String? = nil,
        tags: [String: String]? = nil,
        environment: String? = nil,
        message: Message? = nil,
        exception: Exceptions? = nil,
        breadcrumbs: Breadcrumbs? = nil,
        user: User? = nil
    ) {
        self.event_id = .init(rawValue: event_id)
        self.timestamp = timestamp
        self.platform = platform
        self.level = level
        self.logger = logger
        self.transaction = transaction
        self.server_name = server_name
        self.release = release
        self.tags = tags
        self.environment = environment
        self.message = message
        self.exception = exception
        self.breadcrumbs = breadcrumbs
        self.user = user
    }

    /// Unique identifier of this event.
    /// Hexadecimal string representing a uuid4 value. The length is exactly 32 characters. Dashes are not allowed. Has to be lowercase.
    /// Even though this field is backfilled on the server with a new uuid4, it is strongly recommended to generate that uuid4 clientside.
    /// There are some features like user feedback which are easier to implement that way, and debugging in case events get lost in your Sentry installation is also easier.
    public var event_id: EventId

    /// Indicates when the event was created in the Sentry SDK. The format is a numeric (integer or float) value representing the number of seconds that have elapsed since the Unix epoch.
    public var timestamp: Double

    /// Platform identifier of this event (defaults to "other").
    /// A string representing the platform the SDK is submitting from. This will be used by the Sentry interface to customize various components in the interface.
    /// Acceptable values are: `as3`, `c`, `cfml`, `cocoa`, `csharp`, `elixir`, `haskell`, `go`, `groovy`, `java`, `javascript`, `native`, `node`, `objc`, `other`, `perl`, `php`, `python`, `ruby`
    public var platform: String

    /// The record severity. Defaults to `error`.
    public var level: Level?

    /// The name of the logger which created the record.
    public var logger: String?

    /// The name of the transaction which caused this exception.
    /// For example, in a web app, this might be the route name.
    public var transaction: String?

    /// Server or device name the event was generated on.
    /// This is supposed to be a hostname.
    public var server_name: String?

    /// The release version of the application. Release versions must be unique across all projects in your organization.
    public var release: String?

    /// Optional. A map or list of tags for this event. Each tag must be less than 200 characters.
    public var tags: [String: String]?

    /// The environment name, such as `production` or `staging`.
    public var environment: String?

    /// The Message Interface carries a log message that describes an event or error.
    public var message: Message?

    /// One or multiple chained (nested) exceptions.
    public var exception: Exceptions?

    /// List of breadcrumbs recorded before this event.
    public var breadcrumbs: Breadcrumbs?

    /// Information about the user who triggered this event.
    public var user: User?
}

public enum Level: String, Encodable, Sendable {
    case fatal
    case error
    case warning
    case info
    case debug

    public init(from: Logger.Level) {
        switch from {
        case .trace, .debug:
            self = .debug
        case .info, .notice:
            self = .info
        case .warning:
            self = .warning
        case .error:
            self = .error
        case .critical:
            self = .fatal
        }
    }
}

public enum Message: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case message
        case params
    }

    case raw(message: String)
    case format(message: String, params: [String])

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .raw(let message):
            var container = encoder.singleValueContainer()
            try container.encode(message)
        case .format(let message, let params):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .message)
            try container.encode(params, forKey: .params)
        }
    }
}

public struct Exceptions: Encodable, Sendable {
    public init(values: [ExceptionDataBag]) {
        self.values = values
    }

    public var values: [ExceptionDataBag]
}

public struct ExceptionDataBag: Encodable, Sendable {
    public init(type: String? = nil, value: String? = nil, stacktrace: Stacktrace? = nil) {
        self.type = type
        self.value = value
        self.stacktrace = stacktrace
    }

    /// The type of exception, e.g. `ValueError`.
    /// At least one of `type` or `value` is required, otherwise the exception is discarded.
    public var type: String?

    /// Human readable display value.
    /// At least one of `type` or `value` is required, otherwise the exception is discarded.
    public var value: String?

    /// Stack trace containing frames of this exception.
    public var stacktrace: Stacktrace?
}

public struct Stacktrace: Encodable, Equatable, Sendable {
    public init(frames: [Frame]) {
        self.frames = frames
    }

    /// A non-empty list of stack frames. The list is ordered from caller to callee, or oldest to youngest. The last frame is the one creating the exception.
    public var frames: [Frame]
}

public struct Frame: Encodable, Equatable, Sendable {
    public init(
        filename: String? = nil,
        function: String? = nil,
        raw_function: String? = nil,
        lineno: Int? = nil,
        colno: Int? = nil,
        abs_path: String? = nil,
        instruction_addr: String? = nil
    ) {
        self.filename = filename
        self.function = function
        self.raw_function = raw_function
        self.lineno = lineno
        self.colno = colno
        self.abs_path = abs_path
        self.instruction_addr = instruction_addr
    }

    /// The source file name (basename only).
    public var filename: String?

    /// Name of the frame's function. This might include the name of a class.
    /// This function name may be shortened or demangled. If not, Sentry will demangle and shorten it for some platforms. The original function name will be stored in `raw_function`.
    public var function: String?

    /// A raw (but potentially truncated) function value.
    public var raw_function: String?

    /// Line number within the source file, starting at 1.
    public var lineno: Int?

    /// Column number within the source file, starting at 1.
    public var colno: Int?

    /// Absolute path to the source file.
    public var abs_path: String?

    /// An optional instruction address for symbolication. This should be a string with a hexadecimal number that includes a `0x` prefix. If this is set and a known image is defined in the Debug Meta Interface, then symbolication can take place.
    public var instruction_addr: String?
}

public struct Breadcrumbs: Encodable, Sendable {
    public init(values: [Breadcrumb]) {
        self.values = values
    }

    public var values: [Breadcrumb]
}

public struct Breadcrumb: Encodable, Sendable {
    public init(message: String? = nil, level: Level? = nil, timestamp: Double? = nil) {
        self.message = message
        self.level = level
        self.timestamp = timestamp
    }

    public var message: String?
    public var level: Level?
    public var timestamp: Double?
}

public struct User: Encodable, Sendable {
    public init(id: String, ip_address: String) {
        self.id = id
        self.ip_address = ip_address
    }

    public var id: String
    public var ip_address: String
}
