import Foundation
import Logging

public func evalMetadata(metadata: Logger.Metadata) -> Attachment? {
    if let attachmentValue = metadata["Attachment"],
       case let .stringConvertible(attachmentCon) = attachmentValue,
       let attachment: Attachment = attachmentCon as? Attachment
    {
        return attachment
    }
    return nil
}

public func makeEventData(
    message: String,
    level: Level,
    uid: UUID,
    servername: String?,
    release: String?,
    environment: String?,
    logger: String? = nil,
    transaction: String? = nil,
    tags: [String: String]? = nil,
    filePath: String? = #filePath,
    file: String?,
    function: String? = #function,
    line: Int? = #line
) throws -> Data {
    let frame = Frame(filename: file, function: function, raw_function: nil, lineno: line, colno: nil, abs_path: filePath, instruction_addr: nil)
    let stacktrace = Stacktrace(frames: [frame])
    return try JSONEncoder().encode(Event(
        event_id: uid,
        timestamp: Date().timeIntervalSince1970,
        level: level,
        logger: logger,
        transaction: transaction,
        server_name: servername,
        release: release,
        tags: tags,
        environment: environment,
        message: .raw(message: message),
        exception: Exceptions(values: [ExceptionDataBag(type: message, value: nil, stacktrace: stacktrace)]),
        breadcrumbs: nil,
        user: nil
    ))
}

extension Attachment: CustomStringConvertible {
    public var description: String {
        "Attachment: \(filename)"
    }
}
