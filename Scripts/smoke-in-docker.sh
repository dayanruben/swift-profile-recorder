#!/bin/bash

set -eu

tmpdir=$(mktemp -d /tmp/swipr-smoke_XXXXXX)
swift package resolve # Package.resolved is necessary for 'ro' mount to work
docker run \
    -it --rm \
    -v "$PWD:$PWD:ro" \
    -v "$tmpdir":/output \
    -w "$PWD" \
    --memory $(( 1024 * 1024 * 1024 )) \
    swift:6.0-noble bash -c 'export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install -y curl && Scripts/smoke-test.sh /output'
echo "$tmpdir"
ls "$tmpdir"
