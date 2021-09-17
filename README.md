# Swift Profile Recorder, an in-process sampling profiler

Want to profile your software in restricted Kubernetes or Docker contrainers or other environments where you don't get `CAP_SYS_PTRACE`? Look no further.

## Want to try it out?

```
docker build -t swipr Misc
docker run -it --rm -p 8080:8080  -v "$PWD:$PWD" -w "$PWD" swipr swift run -c release -- swipr-demo 0.0.0.0 8080
```

Then:

- Head to `http://localhost:8080/sample/1` in Safari, save the downloaded file.
- https://profiler.firefox.com
- Drag the downloaded file onto the profiler.
