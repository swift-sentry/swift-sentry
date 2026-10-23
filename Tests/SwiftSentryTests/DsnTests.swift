import Foundation
@testable import SwiftSentry
import Testing

struct DsnTests {
    @Test
    func parseMinimalHttpsDsn() throws {
        let dsn = try Dsn(fromString: "https://public@sentry.example.com/42")
        #expect(dsn.scheme == "https")
        #expect(dsn.host == "sentry.example.com")
        #expect(dsn.port == 443)
        #expect(dsn.publicKey == "public")
        #expect(dsn.secretKey == nil)
        #expect(dsn.projectId == 42)
        #expect(dsn.path == "")
        #expect(dsn.getEnvelopeApiEndpointUrl() == "https://sentry.example.com/api/42/envelope/")
        #expect(dsn.getStoreApiEndpointUrl() == "https://sentry.example.com/api/42/store/")
        #expect(dsn.toString() == "https://public@sentry.example.com/42")
    }

    @Test
    func parseHttpDsnDefaultsToPort80() throws {
        let dsn = try Dsn(fromString: "http://public@localhost/1")
        #expect(dsn.port == 80)
        #expect(dsn.getEnvelopeApiEndpointUrl() == "http://localhost/api/1/envelope/")
    }

    @Test
    func parseDsnWithSecretKeyAndCustomPort() throws {
        let dsn = try Dsn(fromString: "http://public:secret@localhost:9000/7")
        #expect(dsn.publicKey == "public")
        #expect(dsn.secretKey == "secret")
        #expect(dsn.port == 9000)
        #expect(dsn.getEnvelopeApiEndpointUrl() == "http://localhost:9000/api/7/envelope/")
        #expect(dsn.toString() == "http://public:secret@localhost:9000/7")
    }

    @Test
    func defaultPortIsOmittedEvenIfExplicit() throws {
        let dsn = try Dsn(fromString: "https://public@sentry.example.com:443/3")
        #expect(dsn.getEnvelopeApiEndpointUrl() == "https://sentry.example.com/api/3/envelope/")
        #expect(dsn.toString() == "https://public@sentry.example.com/3")
    }

    @Test
    func parseDsnWithPathPrefix() throws {
        let dsn = try Dsn(fromString: "https://public@sentry.example.com/prefix/sub/5")
        #expect(dsn.projectId == 5)
        #expect(dsn.getEnvelopeApiEndpointUrl() == "https://sentry.example.com/prefix/sub/api/5/envelope/")
        #expect(dsn.toString() == "https://public@sentry.example.com/prefix/sub/5")
    }

    @Test
    func authHeader() throws {
        let dsn = try Dsn(fromString: "https://public@sentry.example.com/42")
        let header = dsn.getAuthHeader()
        #expect(header.hasPrefix("Sentry sentry_version=7, "))
        #expect(header.contains("sentry_key=public"))
        #expect(header.contains("sentry_client=\(Sentry.VERSION)"))
        #expect(header.contains("sentry_timestamp="))
    }

    @Test(arguments: [
        "",
        "sentry.example.com/1", // no scheme
        "ftp://public@sentry.example.com/1", // unsupported scheme
        "https://sentry.example.com/1", // no public key
        "https://public@sentry.example.com", // no path
        "https://public@sentry.example.com/abc", // non-numeric project id
        "https://public@sentry.example.com/-1", // negative project id
    ])
    func invalidDsnThrows(_ value: String) {
        let error = #expect(throws: Sentry.SwiftSentryError.self) {
            try Dsn(fromString: value)
        }
        guard case .InvalidArgumentException? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func dsnWithoutProjectIdThrows() {
        let value = "https://public@sentry.example.com/"
        let error = #expect(throws: Sentry.SwiftSentryError.self) {
            try Dsn(fromString: value)
        }
        guard case .InvalidArgumentException(let message)? = error else {
            Issue.record("Unexpected error \(String(describing: error))")
            return
        }
        #expect(message == "The \"\(value)\" DSN must end with a project ID, e.g. \"https://<key>@<host>/<project-id>\".")
    }
}
