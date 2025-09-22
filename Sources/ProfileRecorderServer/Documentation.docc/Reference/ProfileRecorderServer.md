# ``ProfileRecorderServer/ProfileRecorderServer``

## Overview

### Installing the Swift Profile Recorder Server

The Swift Profile Recorder Server is easy to integrate into your application.
First, add a dependency on ProfileRecorder:

```swift
    .package(url: "https://github.com/apple/swift-profile-recorder.git", .upToNextMinor(from: 0.3.0)),

    [...]

    .product(name: "ProfileRecorderServer", package: "swipr"),
```

Within your app, configure and run a sampling server, for example:

```swift
import ProfileRecorderServer

do {
    try await ProfileRecorderServer(
        configuration: try await .parseFromEnvironment()
    ).run(logger: logger)
} catch {
    logger.error("failed to start sampling server", metadata: ["error": "\(error)"])
}
```

The `parseFromEnvironment()` function parses the `SWIPR_SAMPLING_SERVER_URL` & `SWIPR_SAMPLING_SERVER_URL_PATTERN`
environment variables to configure the service.
If you prefer to statically configure it, use:

```swift
var samplingServerConfig = ProfileRecorderServerConfiguration.default
samplingServerConfig.bindTarget = try SocketAddress(ipAddress: "127.0.0.0", port: 7377)
try await ProfileRecorderServer(configuration: samplingServerConfig).run(logger: logger)
```

### Production Configuration

In production, it might be useful to use a UNIX Domain Socket instead of an HTTP server.
If you have access to the filesystem where your app runs, such as a shell in a virtual machine or shell access to a restricted Kubernetes or Docker contrainersrentes pod, use the environment variable `SWIPR_SAMPLING_SERVER_URL_PATTERN` to define a UNIX domain socket to provide the traces.

For example, set `SWIPR_SAMPLING_SERVER_URL_PATTERN="unix:///var/run/swipr-pid-{PID}.sock"`, and Swift Profile Recorder replaces the `{PID}` with the process id from your running app.
In containerised environments, you get files called `/var/run/swipr-pid-1.sock` from this pattern that you can sample using the following command:

```bash
curl -sd '{"numberOfSamples":100,"timeInterval":"10 ms"}' --unix-socket /var/run/swipr/pid-1.sock http://localhost | \
    swift demangle --simplified > /tmp/samples.perf
```

Drag the resulting file into [Firefox Profiler](https://profiler.firefox.com), a client-side web app, to see a visualization of the traces. 

## Topics

### Creating a sampling server

- ``init(configuration:)``
- ``ProfileRecorderServerConfiguration``

### Inspecting the sampling server

- ``configuration``

### Running the sampling server

- ``run(logger:)``
- ``withSamplingServer(logger:_:)``
- ``ServerInfo``

