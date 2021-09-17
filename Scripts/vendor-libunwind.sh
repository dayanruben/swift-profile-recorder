#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift Profile Recorder open source project
##
## Copyright (c) 2021 Apple Inc. and the Swift Profile Recorder project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -eu

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
libunwind=${1:-$here/../../llvm-project/libunwind}
prefix=${2:-swipr}

function die() {
    echo "ERROR: $*"
    exit 1
}

echo "Using libunwind from $libunwind"
test -d "$libunwind" || die "$libunwind: Not found"

target_src="$here/../Sources/CProfileRecorderLibUnwind"
desc=$(cd "$libunwind" && git describe --abbrev --dirty)

rm -rf "$target_src"
mkdir "$target_src"
cp -R "$libunwind/src"/* "$target_src"
mkdir "$target_src/include"
cp "$libunwind/include"/*.h "$target_src/include"
cp -R "$libunwind/include/mach-o" "$target_src/"
cat > "$target_src/include/CProfileRecorderLibUnwind.h" <<"EOF"
#ifndef CProfileRecorderLibUnwind_h
#define CProfileRecorderLibUnwind_h

#include "unwind.h"
#include "libunwind.h"

#endif
EOF

echo "$desc" > "$here/../Misc/vendored-libunwind.version"
rm -f "$target_src/include/unwind_arm_ehabi.h"\
      "$target_src/CMakeLists.txt"

find Sources/CProfileRecorderLibUnwind/ \
    -type f \
    -exec gsed -ri \
        -e "s/\<unw_/${prefix}_unw_/g" \
        -e "s/\<_Unwind_/_${prefix}_Unwind_/g" \
        -e "s/\<__unw_/__${prefix}_unw_/g" \
        -e "s/\<__(de|)register_frame/__${prefix}_\1register_frame/g" \
        -e 's#include .mach-o/compact_unwind_encoding.h.#include "mach-o/compact_unwind_encoding.h"#g' \
        '{}' \;
echo "Okay, all done."
