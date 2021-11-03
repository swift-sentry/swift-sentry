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
