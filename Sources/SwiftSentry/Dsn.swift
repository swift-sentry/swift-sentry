//
//  Dsn.swift
//  SwiftSentry
//
//  Created by AZm87 on 24.06.21.
//

import Foundation

/// This class represents a Sentry DSN that can be obtained from the Settings page of a project.
struct Dsn {
    /// The protocol to be used to access the resource
    let scheme: String

    /// The host that holds the resource
    let host: String

    /// The port on which the resource is exposed
    let port: Int

    /// The public key to authenticate the SDK
    let publicKey: String

    /// The secret key to authenticate the SDK
    let secretKey: String?

    /// The ID of the resource to access
    let projectId: Int

    /// The specific resource that the web client wants to access
    let path: String

    /**
     * Class constructor.
     *
     * - parameters:
     *   - scheme: The protocol to be used to access the resource
     *   - host: The host that holds the resource
     *   - port: The port on which the resource is exposed
     *   - projectId: The ID of the resource to access
     *   - path: The specific resource that the web client wants to access
     *   - publicKey: The public key to authenticate the SDK
     *   - secretKey: The secret key to authenticate the SDK
     */
    init(scheme: String, host: String, port: Int, projectId: Int, path: String, publicKey: String, secretKey: String?) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.publicKey = publicKey
        self.secretKey = secretKey
        self.path = path
        self.projectId = projectId
    }

    /**
     * Creates an instance of this class by parsing the given string.
     *
     * - parameters:
     *   - value: The string to parse
     */
    init(fromString value: String) throws {
        guard let parsedDsn = URL(string: value) else {
            throw Sentry.SwiftSentryError.InvalidArgumentException("The \"\(value)\" DSN is invalid.")
        }

        guard let scheme = parsedDsn.scheme, !scheme.isEmpty else {
            throw Sentry.SwiftSentryError.InvalidArgumentException("The \"\(value)\" DSN must contain a scheme, a host, a user and a path component.")
        }

        guard let host = parsedDsn.host, !host.isEmpty else {
            throw Sentry.SwiftSentryError.InvalidArgumentException("The \"\(value)\" DSN must contain a scheme, a host, a user and a path component.")
        }

        let path = parsedDsn.path
        guard !path.isEmpty else {
            throw Sentry.SwiftSentryError.InvalidArgumentException("The \"\(value)\" DSN must contain a scheme, a host, a user and a path component.")
        }

        guard let user = parsedDsn.user, !user.isEmpty else {
            throw Sentry.SwiftSentryError.InvalidArgumentException("The \"\(value)\" DSN must contain a scheme, a host, a user and a path component.")
        }

        if let pass = parsedDsn.password {
            guard !pass.isEmpty else {
                throw Sentry.SwiftSentryError.InvalidArgumentException("The \"\(value)\" DSN must contain a valid secret key.")
            }
        }

        guard scheme == "http" || scheme == "https" else {
            throw Sentry.SwiftSentryError.InvalidArgumentException("The scheme of the \"\(value)\" DSN must be either \"http\" or \"https\".")
        }

        var segmentPaths = path.split(separator: "/", omittingEmptySubsequences: true)

        guard let projectId = Int(segmentPaths.removeLast()), projectId >= 0 else {
            throw Sentry.SwiftSentryError.InvalidArgumentException("\"\(value)\" DSN must contain a valid project ID.")
        }

        self.init(
            scheme: scheme,
            host: host,
            port: parsedDsn.port ?? (scheme == "http" ? 80 : 443),
            projectId: projectId,
            path: segmentPaths.joined(separator: "/"),
            publicKey: user,
            secretKey: parsedDsn.password
        )
    }

    /// Returns the URL of the API for the store endpoint.
    public func getStoreApiEndpointUrl() -> String {
        getBaseEndpointUrl() + "/store/"
    }

    /// Returns the URL of the API for the envelope endpoint.
    public func getEnvelopeApiEndpointUrl() -> String {
        getBaseEndpointUrl() + "/envelope/"
    }

    public func getAuthHeader() -> String {
        "Sentry sentry_version=7, sentry_key=\(publicKey), sentry_client=\(Sentry.VERSION), sentry_timestamp=\(Date().timeIntervalSince1970)"
    }

    /// @see https://www.php.net/manual/en/language.oop5.magic.php#object.tostring
    public func toString() -> String {
        var url = "\(scheme)://\(publicKey)"

        if let secretKey = secretKey {
            url += ":\(secretKey)"
        }

        url += "@\(host)"

        if (scheme == "http" && port != 80) || (scheme == "https" && port != 443) {
            url += ":\(port)"
        }

        url += "\(path)/\(projectId)"

        return url
    }

    /// Returns the base url to Sentry from the DSN.
    private func getBaseEndpointUrl() -> String {
        var url = "\(scheme)://\(host)"

        if (scheme == "http" && port != 80) || (scheme == "https" && port != 443) {
            url += ":\(port)"
        }

        url += "\(path)/api/\(projectId)"

        return url
    }
}
