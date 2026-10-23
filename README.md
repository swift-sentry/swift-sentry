# SwiftSentry

![Swift 5](https://img.shields.io/badge/Swift-5-orange.svg) ![SPM](https://img.shields.io/badge/SPM-compatible-green.svg) ![Platforms](https://img.shields.io/badge/Platforms-macOS%20Linux-green.svg) [![Test](https://github.com/swift-sentry/swift-sentry/actions/workflows/test.yml/badge.svg)](https://github.com/swift-sentry/swift-sentry/actions/workflows/test.yml) [![codebeat badge](https://codebeat.co/badges/b4f3753c-c753-4479-8bc2-53fb5892093f)](https://codebeat.co/projects/github-com-swift-sentry-swift-sentry-main)

Log messages from Swift to Sentry following [SwiftLog](https://github.com/apple/swift-log).

## Usage
1. Add `SwiftSentry` as a dependency to your `Package.swift`

```swift
  dependencies: [
    .package(name: "SwiftSentry", url: "https://github.com/swift-sentry/swift-sentry.git", from: "1.0.0")
  ],
  targets: [
    .target(name: "MyApp", dependencies: ["SwiftSentry"])
  ]
```

2. Configure Logging system

```swift
import Logging
import SwiftSentry

let sentry = Sentry(dsn: "<Your Sentry DSN String>")

// Add sentry to logger and set the minimum log level to `.error`
LoggingSystem.bootstrap { label in
    MultiplexLogHandler([
        SentryLogHandler(label: label, sentry: sentry, level: .error),
        StreamLogHandler.standardOutput(label: label)
    ])
}
```

If your application already uses a `EventLoopGroup` it is recommended to share it with SwiftSentry:

```swift
let sentry = try Sentry(
  dsn: "<Your Sentry DSN String>",
  httpClient: HTTPClient(eventLoopGroupProvider: .shared(eventLoopGroup))
)
```

3. Send logs

```swift
var logger = Logger(label: "com.example.MyApp.main")
logger.critical("Something went wrong!")
```

The metadata of the logger will be sent as tags to sentry.

```swift
logger[metadataKey: "note"] = Logger.MetadataValue(stringLiteral: "some usefull information")
```

## Upload crash reports
SwiftSentry can also upload stack traces generated on Linux with [Swift Backtrace](https://github.com/swift-server/swift-backtrace).

The following configuration assumes that you run an "API service" based on Swift with `supervisord` following a typical [vapor deployment](https://docs.vapor.codes/4.0/deploy/supervisor/).

Stack traces are uploaded at each start of your "API service". If your application crashes, a stack trace will be printed on `stderr` and written to a log file specified in `supervisord`. Once your application is restarted, SwiftSentry will read this log file and upload it to Sentry.

```swift
import SwiftSentry

let sentry = Sentry(dsn: "<Your Sentry DSN String>")

// Upload stack trace from a log file
// WARNING: the error file will be truncated afterwards
_ = try? sentry.uploadStackTrace(path: "/var/log/supervisor/hello-stderr.log")
```


Supervisor configuration at `/etc/supervisor/conf.d/hello.conf`:

```
[program:hello]
command=/home/vapor/hello/.build/release/Run serve --env production
directory=/home/vapor/hello/
user=vapor
stdout_logfile=/var/log/supervisor/%(program_name)-stdout.log
stderr_logfile=/var/log/supervisor/%(program_name)-stderr.log
```

## Running tests

```sh
swift test
```

### Integration tests
The integration tests in `IntegrationTests.swift` send real envelopes to a Sentry-compatible server. They only run if the environment variable `SENTRY_INTEGRATION_DSN` contains a DSN; otherwise the suite is skipped. A dedicated variable is used instead of `SENTRY_DSN` so test events never reach a project that happens to be configured in your environment.

`compose.yml` starts a local [GlitchTip](https://glitchtip.com) server, which implements the Sentry ingest protocol. It needs Docker (or Podman) with Compose.

```sh
# Start the server; returns once it is healthy (~15 s)
docker compose up -d --wait

# Look up the DSN of the bootstrapped project
export SENTRY_INTEGRATION_DSN=$(curl -s \
  -H "Authorization: Bearer $(printf 'd%.0s' {1..64})" \
  http://localhost:8000/api/0/projects/org/project/keys/ | jq -r '.[0].dsn.public')

swift test

# Stop the server and discard its data
docker compose down -v
```

The server keeps its data in memory only, so its DSN changes every time the containers are recreated. Look it up again after each `docker compose up`.

To inspect the received events, log in at http://localhost:8000 with `test@example.com` / `admin_pass`. If port 8000 is already taken, start the server with `SENTRY_PORT=8001 docker compose up -d --wait` and use that port in the commands above.

You can also point `SENTRY_INTEGRATION_DSN` at a real Sentry project. Use a project meant for testing, because every test run creates events there.

# TODO
- Capture stack traces for all logs (See [Vapor Stacktrace implementation](https://github.com/vapor/vapor/blob/73d57959a96ceca719558e70c320b2f729d2b25b/Sources/Vapor/Error/StackTrace.swift))
- Additional repository `SentryVapor` to abtract logging with vapor requests. E.g. log hostnames, url, request-id
