import Foundation

struct FatalError {
    /// The error message that is produced from a fatal error
    let message: String
    
    let stacktrace: Stacktrace
    
    /// Parse an error log that contains multiple fatal errors with stacktraces from SwiftBacktrace
    internal static func parseStacktrace(_ string: String) -> [FatalError] {
        let lines = string.split(separator: "\n")
        var result = [FatalError]()

        var stacktraceFound = false
        var frames = [Frame]()
        var errorMessage = [String]()

        for l in lines {
            let line = l.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                continue
            }

            switch (line.starts(with: "0x"), stacktraceFound) {
            case (true, _):
                // found a line of the stacktrace
                stacktraceFound = true

                if let posComma = line.firstIndex(of: ","), let posAt = line.range(of: " at /"), let posColon = line.lastIndex(of: ":") {
                    let addr = String(line[line.startIndex ..< posComma])
                    let functionName = String(line[line.index(posComma, offsetBy: 2) ..< posAt.lowerBound])
                    let path = String(line[line.index(before: posAt.upperBound) ..< posColon])
                    let lineno = Int(line[line.index(posColon, offsetBy: 1) ..< line.endIndex])

                    frames.insert(Frame(filename: nil, function: functionName, raw_function: nil, lineno: lineno, colno: nil, abs_path: path, instruction_addr: addr), at: 0)
                } else {
                    frames.insert(Frame(filename: nil, function: nil, raw_function: nil, lineno: nil, colno: nil, abs_path: nil, instruction_addr: line), at: 0)
                }
            case (false, false):
                // found another header line
                errorMessage.append(line)
            case (false, true):
                // if we find a non stacktrace line after a stacktrace, its a new error -> send current error to sentry and start a new error event
                let message = errorMessage.joined(separator: "\n")
                let stacktrace = Stacktrace(frames: frames)
                let messageWithStacktrace = FatalError(message: message, stacktrace: stacktrace)
                result.append(messageWithStacktrace)
                stacktraceFound = false
                frames = [Frame]()
                errorMessage = [line]
            }
        }

        if !frames.isEmpty || !errorMessage.isEmpty {
            let message = errorMessage.joined(separator: "\n")
            let stacktrace = Stacktrace(frames: frames)
            let messageWithStacktrace = FatalError(message: message, stacktrace: stacktrace)
            result.append(messageWithStacktrace)
        }

        return result
    }
    
    /// Generate a `Event` object to upload to sentry
    func getEvent(servername: String?, release: String?, environment: String?) -> Event {
        Event(
            event_id: UUID(),
            timestamp: Date().timeIntervalSince1970,
            level: .fatal,
            logger: nil,
            transaction: nil,
            server_name: servername,
            release: release,
            tags: nil,
            environment: environment,
            message: .raw(message: message),
            exception: Exceptions(values: [ExceptionDataBag(type: "FatalError", value: message, stacktrace: stacktrace)]),
            breadcrumbs: nil,
            user: nil
        )
    }
}
