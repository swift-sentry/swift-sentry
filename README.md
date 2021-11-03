# SwiftSentry

![Swift 5](https://img.shields.io/badge/Swift-5-orange.svg) ![SPM](https://img.shields.io/badge/SPM-compatible-green.svg) ![Platforms](https://img.shields.io/badge/Platforms-macOS%20Linux-green.svg) [![Test](https://github.com/swift-sentry/swift-sentry/actions/workflows/test.yml/badge.svg)](https://github.com/swift-sentry/swift-sentry/actions/workflows/test.yml) [![codebeat badge](https://codebeat.co/badges/b4f3753c-c753-4479-8bc2-53fb5892093f)](https://codebeat.co/projects/github-com-swift-sentry-swift-sentry-main)

Log messages from Swift to Sentry following [SwiftLog](https://github.com/apple/swift-log).

WARNING: Under development!

## Usage
1. Add `SwiftSentry` as a dependency to your `Package.swift`

```swift
  dependencies: [
    .package(url: "https://github.com/swift-sentry/swift-sentry.git", from: "1.0.0")
  ],
  targets: [
    .target(name: "MyApp", dependencies: ["SwiftSentry"])
  ]
```

2. Configure Logging system

```swift
import Logging
import SwiftSentry

let sentry = SwiftSentry(dsn: "https://bdff91e76.....@o4885.....ingest.sentry.io/5609....")

// Add sentry to logger and set the minimum log level to `.error`
LoggingSystem.bootstrap { label in
    MultiplexLogHandler([
        SentryLogHandler(label: label, sentry: sentry, level: .error),
        StreamLogHandler.standardOutput(label: label)
    ])
}

// The default minimum log level can also be set
SentryLogHandler.defaultLogLevel = .error
```

3. Send logs

```swift
let logger = Logger(label: "com.example.MyApp.main")

logger.critical("Something went wrong!")
```

## Upload crash reports
SwiftSentry can also upload stack traces generated on Linux with [Swift Backtrace](https://github.com/swift-server/swift-backtrace).

The following configuration assumes that you run an "API service" based on Swift with `supervisord` following a typical [vapor deployment](https://docs.vapor.codes/4.0/deploy/supervisor/).

Stack traces are uploaded at each start of your "API service". If your application crashes, a stack trace will be printed on `stderr` and written to a log file specified in `supervisord`. Once your application is restarted, SwiftSentry will read this log file and upload it to Sentry. Because 

```swift
import SwiftSentry

let sentry = SwiftSentry(dsn: "https://bdff91e76.....@o4885.....ingest.sentry.io/5609....")

// Upload stack trace from a log file
// WARNING: the error file will be truncated afterwards
sentry.uploadStackTrace(path: "/var/log/supervisor/hello-stderr.log")
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
