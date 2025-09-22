# Swift Profile Recorder, an in-process sampling profiler

Want to profile your software in restricted Kubernetes or Docker contrainers or other environments where you don't get `CAP_SYS_PTRACE`? Look no further.

## What is this?

This is a sampling profiler (like `sample` on macOS) with the special twist that it runs _inside_ the process that gets sampled. This means that it doesn't need `CAP_SYS_PTRACE` or any other privileges to work.

You can pull it in as a fully self-contained Swift Package Manger dependency and then use it for your app.

### Supported OSes

At the moment, it only supports Linux and macOS.
This could also support iOS and any other UNIX-like OS but it's not implemented at this point in time.

## How can I use it?

### Via Swift Profile Recorder Server

The easiest way to use Swift Profile Recorder in your application is to make it run the Swift Profile Recorder Server.
This allows you to retrieve symbolicated samples with a single `curl` (or any other HTTP client) command.

#### Using the Sampling Server

Once you have bootstraped the Swift Profile Recorder Server in your application, you can request samples the following way:

1. Set the environment variable `SWIPR_SAMPLING_SERVER_URL=http://127.0.0.1:7377` and run your server
2. Request the samples

```bash
curl -sd '{"numberOfSamples":100,"timeInterval":"10 ms"}' http://localhost:7377 | \
    swift demangle --simplified > /tmp/samples.perf
```
3. Visualise the traces (see below)

#### Visualisation

##### FlameGraphs

Repository: https://github.com/brendangregg/Flamegraph

```bash
FlameGraph/stackcollapse-perf.pl < /tmp/samples.perf | FlameGraph/flamegraph.pl > /tmp/samples.svg
open /tmp/samples.svg
```

##### Firefox Profiler (https://profiler.firefox.com):

How to use Firefox Profiler?

1. Open https://profiler.firefox.com and drag /tmp/samples.svg onto it.
2. Click "Show all tracks" in "tracks" menu on the top left
3. Slightly further down, select the first thread (track), hold Shift and select the last thread.
4. Open the "Flame Graph" tab

##### Pyroscope

[Pyroscope](https://pyroscope.io) is an OSS continuous profiling service. You can submit Swift Profile Recorder samples into Pyroscope by
running the following command (for example in a loop).

```
curl -s -d '{"numberOfSamples":100,"timeInterval":"100 ms"}' --unix-socket /var/run/swipr-pid-1.sock http://unix | \
    c++filt -n | swift demangle --simplified | \
    FlameGraph/stackcollapse-perf.pl | \
    cut -d';' -f2- | \
    curl --data-binary @- "http://YOUR_PYROSCOPE_SERVER:4040/ingest?name=YOUR_APP&sampleRate=10&from=$(( $(date +%s) - 10 ))"
```

##### Other options

Check https://profilerpedia.markhansen.co.nz/formats/linux-perf-script/#converts-to-transitive for
a list of visualisation options for the "Linux perf script" format that Swift Profile Recorder produces.

#### Configuration in production

In production, it might be useful to use a UNIX Domain Socket instead of a HTTP server in which case you might want to
set `SWIPR_SAMPLING_SERVER_URL_PATTERN="unix:///var/run/swipr-pid-{PID}.sock"`. Swift Profile Recorder will replace the `{PID}` by the pid.
In containerised environments, you'll then get files called `/var/run/swipr-pid-1.sock` etc that you can sample using

```bash
curl -sd '{"numberOfSamples":100,"timeInterval":"10 ms"}' --unix-socket /var/run/swipr/pid-1.sock http://localhost | \
    swift demangle --simplified > /tmp/samples.perf
```

### Installing the Swift Profile Recorder Server

The Swift Profile Recorder Server is easy to integrate into your application. First, add a dependency on ProfileRecorder:

```swift
    .package(url: "https://github.com/apple/swift-profile-recorder.git", .upToNextMinor(from: 0.3.0)),
        
    [...]
        
    .product(name: "ProfileRecorderServer", package: "swipr"),
```

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

The `parseFromEnvironment()` function will parse the `SWIPR_SAMPLING_SERVER_URL` & `SWIPR_SAMPLING_SERVER_URL_PATTERN`
environment variables. If you prefer to statically configure it, use

```swift
var samplingServerConfig = ProfileRecorderServerConfiguration.default
samplingServerConfig.bindTarget = try SocketAddress(ipAddress: "127.0.0.0", port: 7377)
try await ProfileRecorderServer(configuration: samplingServerConfig).run(logger: logger)
```


### What's the API for requesting samples yourself?

It's very simple. When you want a sample of your app, run for example

```swift
ProfileRecorderSampler.sharedInstance.requestSamples(
    outputFilePath: "/tmp/samples",
    count: 1_000,
    timeBetweenSamples: .milliseconds(10),
    eventLoop: loop
)
```

which will create 1000 samples with 10 ms between them. So it'll sample for
about 10 seconds. After that, you'll need to (on the machine you're running it)
convert the samples into a regular format, and also symbolicate it.

Optionally, you can have `llvm-symbolizer` symbolise your samples, you can request this by passing `--use-native-symbolizer false` to
`swipr-sample-conv`. By default (as of Swift Profile Recorder 0.2.6), it will use ProfileRecorder's native symboliser.

That can be done using

```bash
swipr-sample-conv < /tmp/samples | swift demangle --simplified > /tmp/stacks.perf
```

**NOTE**: `swipr-sample-conv` _must_ be run on a system that has access to the very same files in the same versions as the system where the samples were obtained. Usually this means that you need to run them in a Docker container with the exact same image as what you were running in prod. It can be another container but it needs to have the same files at the same paths (to be able to symbolicate).

The resulting file, you can just drag into [Firefox Profiler](https://profiler.firefox.com)
which is a client-side web app.

### Want to see an example?

The project includes a demo app that embeds a sampling server.
Build and run it:

```bash
swift build -c release
SWIPR_SAMPLING_SERVER_URL=unix:///tmp/swipr.sock \
    .build/release/swipr-mini-demo \
    --blocking --burn-cpu --array-appends \
    --output "$output"/samples.swipr \
    --iterations 10000 \
    --sampling-server
```

In another terminal, retrieve the symbols:

```bash
curl -o /tmp/samples.perf \
    -sd '{"timeInterval":"100 ms","numberOfSamples":100}' \
    --unix-socket /tmp/swipr.sock http://localhost/sample
```

- Open https://profiler.firefox.com in your browser
- Drag the file at `/tmp/samples.perf` onto the browser window to see the traces with the Firefox profiler app.
