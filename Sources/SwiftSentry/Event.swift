//
//  Event.swift
//  SwiftSentry
//
//  Created by AZm87 on 14.07.21.
//

import Foundation
import Logging

// docs at https://develop.sentry.dev/sdk/event-payloads/
struct Event: Encodable {
    /// Unique identifier of this event.
    /// Hexadecimal string representing a uuid4 value. The length is exactly 32 characters. Dashes are not allowed. Has to be lowercase.
    /// Even though this field is backfilled on the server with a new uuid4, it is strongly recommended to generate that uuid4 clientside.
    /// There are some features like user feedback which are easier to implement that way, and debugging in case events get lost in your Sentry installation is also easier.
    @UUIDHexadecimalEncoded
    var event_id: UUID

    /// Indicates when the event was created in the Sentry SDK. The format is a numeric (integer or float) value representing the number of seconds that have elapsed since the Unix epoch.
    let timestamp: Double

    /// Platform identifier of this event (defaults to "other").
    /// A string representing the platform the SDK is submitting from. This will be used by the Sentry interface to customize various components in the interface.
    /// Acceptable values are: `as3`, `c`, `cfml`, `cocoa`, `csharp`, `elixir`, `haskell`, `go`, `groovy`, `java`, `javascript`, `native`, `node`, `objc`, `other`, `perl`, `php`, `python`, `ruby`
    let platform: String = "other"

    /// The record severity. Defaults to `error`.
    let level: Level?

    /// The name of the logger which created the record.
    let logger: String?

    /// The name of the transaction which caused this exception.
    /// For example, in a web app, this might be the route name.
    let transaction: String?

    /// Server or device name the event was generated on.
    /// This is supposed to be a hostname.
    let server_name: String?

    /// The release version of the application. Release versions must be unique across all projects in your organization.
    let release: String?

    /// Optional. A map or list of tags for this event. Each tag must be less than 200 characters.
    let tags: [String: String]?

    /// The environment name, such as `production` or `staging`.
    let environment: String?

    /// The Message Interface carries a log message that describes an event or error.
    let message: Message?

    /// One or multiple chained (nested) exceptions.
    let exception: Exceptions?

    /// List of breadcrumbs recorded before this event.
    let breadcrumbs: Breadcrumbs?

    /// Information about the user who triggered this event.
    let user: User?
}

enum Level: String, Encodable {
    case fatal
    case error
    case warning
    case info
    case debug

    init(from: Logger.Level) {
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

enum Message: Encodable {
    enum CodingKeys: String, CodingKey {
        case message
        case params
    }

    case raw(message: String)
    case format(message: String, params: [String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .raw(let message):
            try container.encode(message, forKey: .message)
        case .format(let message, let params):
            try container.encode(message, forKey: .message)
            try container.encode(params, forKey: .params)
        }
    }
}

struct Exceptions: Encodable {
    let values: [ExceptionDataBag]
}

struct ExceptionDataBag: Encodable {
    /// The type of exception, e.g. `ValueError`.
    /// At least one of `type` or `value` is required, otherwise the exception is discarded.
    let type: String?

    /// Human readable display value.
    /// At least one of `type` or `value` is required, otherwise the exception is discarded.
    let value: String?

    /// Stack trace containing frames of this exception.
    let stacktrace: Stacktrace?
}

struct Stacktrace: Encodable, Equatable {
    /// A non-empty list of stack frames. The list is ordered from caller to callee, or oldest to youngest. The last frame is the one creating the exception.
    let frames: [Frame]
}

struct Frame: Encodable, Equatable {
    /// The source file name (basename only).
    let filename: String?

    /// Name of the frame's function. This might include the name of a class.
    /// This function name may be shortened or demangled. If not, Sentry will demangle and shorten it for some platforms. The original function name will be stored in `raw_function`.
    let function: String?

    /// A raw (but potentially truncated) function value.
    let raw_function: String?

    /// Line number within the source file, starting at 1.
    let lineno: Int?

    /// Column number within the source file, starting at 1.
    let colno: Int?

    /// Absolute path to the source file.
    let abs_path: String?

    /// An optional instruction address for symbolication. This should be a string with a hexadecimal number that includes a `0x` prefix. If this is set and a known image is defined in the Debug Meta Interface, then symbolication can take place.
    let instruction_addr: String?
}

struct Breadcrumbs: Encodable {
    let values: [Breadcrumb]
}

struct Breadcrumb: Encodable {
    let message: String?
    let level: Level?
    let timestamp: Double?

    init(message: String? = nil, level: Level? = nil, timestamp: Double? = nil) {
        self.message = message
        self.level = level
        self.timestamp = timestamp
    }
}

struct User: Encodable {
    let id: String
    let ip_address: String
}
