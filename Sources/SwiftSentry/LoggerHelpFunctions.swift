import Foundation
import Logging

public struct LimitedEvent: Encodable {
    @UUIDHexadecimalEncoded
    var event_id: UUID

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
}

public func evalMetadata(metadata: Logger.Metadata) -> Attachment? {
    if let filenameValue = metadata["AttachmentFileName"],
       case let .string(filename) = filenameValue
    {
        if let attachmentDataValue = metadata["AttachmentData"],
           case let .stringConvertible(dataCon) = attachmentDataValue,
           let data: Data = dataCon as? Data
        {
            return .init(data: data, filename: filename)
        }
        if let attachmentPathValue = metadata["AttachmentPath"],
           case let .string(path) = attachmentPathValue
        {
            do {
                return try .init(path: path, filename: filename)
            } catch {
                return nil
            }
        }
    }

    if let attachmentPathValue = metadata["AttachmentPath"],
       case let .string(path) = attachmentPathValue
    {
        do {
            return try .init(path: path)
        } catch {
            return nil
        }
    }
    return nil
}
