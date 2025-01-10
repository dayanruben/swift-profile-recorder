#!/bin/bash

set -eu

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$here"
swift build -c release --scratch-path /root/build
mkdir -p /output

SWIPR_SAMPLING_SERVER_URL=unix:///tmp/foo.sock \
    /root/build/release/swipr-mini-demo \
    --blocking  --burn-cpu --array-appends \
    --output /output/samples.swipr \
    --iterations 50 \
    --sampling-server &
demo_pid=$!
sleep 3
curl -o /output/samples.perf \
    -sd '{"timeInterval":"100 ms","numberOfSamples":100}' \
    --unix-socket /tmp/foo.sock \
    http://unix/sample
curl -o /output/samples.pprof \
    -sd '{"timeInterval":"100 ms","numberOfSamples":100, "format": "pprofSymbolized"}' \
    --unix-socket /tmp/foo.sock \
    http://unix/sample
wait "$demo_pid"
