#!/bin/bash

set -eu

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
libunwind=${1:-$here/../../llvm-project/libunwind}
prefix=${2:-swift_unwind}

function die() {
    echo "ERROR: $*"
    exit 1
}

echo "Using libunwind from $libunwind"
test -d "$libunwind" || die "$libunwind: Not found"

target_src="$here/../Sources/CLibUnwind"
desc=$(cd "$libunwind" && git describe --abbrev --dirty)

rm -rf "$target_src"
mkdir "$target_src"
cp -R "$libunwind/src"/* "$target_src"
mkdir "$target_src/include"
cp -R "$libunwind/include"/* "$target_src/include"

echo "$desc" > "$here/../Misc/vendored-libunwind.version"
rm -f "$target_src/include/unwind_arm_ehabi.h"\
      "$target_src/CMakeLists.txt"

find Sources/CLibUnwind/ \
    -type f \
    -exec gsed -ri \
        -e "s/\<unw_/${prefix}_unw_/g" \
        -e "s/\<_Unwind_/_${prefix}_Unwind_/g" \
        -e "s/\<__unw_/__${prefix}_unw_/g" \
        -e "s/\<__(de|)register_frame/__${prefix}_\1register_frame/g" "{}" \;
echo "Okay, all done."
