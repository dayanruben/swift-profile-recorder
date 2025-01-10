#!/bin/bash

set -eu

tmpdir=$(mktemp -d /tmp/swipr-smoke_XXXXXX)
docker run -it --rm -v "$PWD:$PWD:ro" -v "$tmpdir":/output -w "$PWD" swift:6.0-noble Scripts/smoke-test.sh
echo "$tmpdir"
ls "$tmpdir"
