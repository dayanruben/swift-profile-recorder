#!/bin/bash

set -eu

tmpdir=$(mktemp -d /tmp/swipr-smoke_XXXXXX)
docker run \
    -it --rm \
    -v "$PWD:$PWD:ro" \
    -v "$tmpdir":/output \
    -w "$PWD" \
    --memory $(( 1024 * 1024 * 1024 )) \
    swift:6.0-noble Scripts/smoke-test.sh /output
echo "$tmpdir"
ls "$tmpdir"
