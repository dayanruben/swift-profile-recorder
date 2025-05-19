#!/bin/bash

set -eu

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$here"
swift build -c release --scratch-path /root/build
mkdir -p /output

rm -f /tmp/foo.sock
SWIPR_SAMPLING_SERVER_URL=unix:///tmp/foo.sock \
    /root/build/release/swipr-mini-demo \
    --blocking  --burn-cpu --array-appends \
    --output /output/samples.swipr \
    --iterations 1000 \
    --sampling-server &
demo_pid=$!
sleep 3

set -x
curl -o /output/samples.perf \
    -sd '{"timeInterval":"100 ms","numberOfSamples":100}' \
    --unix-socket /tmp/foo.sock \
    http://unix/sample
curl -o /output/samples.pprof \
    -s \
    --unix-socket /tmp/foo.sock \
    http://unix/debug/pprof/profile?seconds=10
curl -o /output/samples-fakesym.pprof \
    -s \
    --unix-socket /tmp/foo.sock \
    http://unix/debug/pprof/symbolizer=fake/profile?seconds=10
kill "$demo_pid"
wait "$demo_pid" || true
