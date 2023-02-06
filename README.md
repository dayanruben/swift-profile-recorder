# Swift Profile Recorder, an in-process sampling profiler

Want to profile your software in restricted Kubernetes or Docker contrainers or other environments where you don't get `CAP_SYS_PTRACE`? Look no further.

## What is this?

This is a sampling profiler (like `sample` on macOS) with the special twist that it runs _inside_ the process that gets sampled. This means that it doesn't need `CAP_SYS_PTRACE` or any other privileges to work.

You can pull it in as a fully self-contained Swift Package Manger dependency and then use it for your app.

### Supported OSes

At the moment, it only supports Linux. This could totally also support macOS, iOS, and any other UNIX-like OS but it's not implemented at this point in time.

## How can I use it?

### What's the API?

It's very simple. When you want a sample of your app, run for example

```swift
ProfileRecorderSampler.sharedInstance.requestSamples(outputFilePath: "/tmp/samples",
                                           count: 1_000,
                                           timeBetweenSamples: .milliseconds(10),
                                           eventLoop: loop)
```

which will create 1000 samples with 10 ms between them. So it'll sample for
about 10 seconds. After that, you'll need to (on the machine you're running it)
convert the samples into a regular format, and also symbolicate it.

You need to have `llvm-symbolizer` installed for `swipr-sample-cov` to work.

That can be done using

```bash
swipr-sample-conv < /tmp/samples | swift demangle > /tmp/stacks.perf
```

The resulting file, you can just drag into [Firefox Profiler](https://profiler.firefox.com)
which is a client-side web app.









### Want to try it out?

After running the following commands, you'll have a web server running that can sample itself.

```bash
docker build -t swipr Misc
docker run -it --rm -p 8080:8080  -v "$PWD:$PWD" -w "$PWD" swipr swift run -c release -- swipr-demo 0.0.0.0 8080
```

Then:

- Head to `http://localhost:8080/sample/10` in Safari, the request will "hang"
- Whilst the sample is running (should be about 20 seconds) you should generate some load to `http://localhost:8080/dynamic/info` or so (for example using `wrk`) to make the sample more interesting.
- Once your browser has downloaded the file, the sample is complete.
- Head to https://profiler.firefox.com
- Drag the downloaded file onto the Firefox Profiler.
