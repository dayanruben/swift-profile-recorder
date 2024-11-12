#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift Profile Recorder open source project
##
## Copyright (c) 2024 Apple Inc. and the Swift Profile Recorder project authors
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
swift_root=${1:-$here/../../swift}
backtracing_root="$swift_root"/stdlib/public/RuntimeModule
prefix=${2:-SWIPR}

function die() {
    echo "ERROR: $*"
    exit 1
}

echo "Using backtracing_root from $backtracing_root"
test -d "$backtracing_root" || die "$backtracing_root: Not found"

target_c_src="$here/../Sources/CProfileRecorderSwiftELF"
target_swift_src="$here/../Sources/ProfileRecorderSampleConversion/NativeSymboliser"
desc=$(cd "$backtracing_root" && git describe --abbrev --dirty)

rm -rf "$target_c_src" "$target_swift_src"
mkdir -p "$target_c_src/include"
mkdir -p "$target_swift_src"
cat > "$target_c_src/empty.c" <<"EOF"
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
EOF
cat > "$target_c_src/include/CProfileRecorderSwiftELF.h" <<"EOF"
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#ifndef CProfileRecorderSWIFTELF_h
#define CProfileRecorderSWIFTELF_h

#include "elf.h"
#include "eh_frame_hdr.h"
#include "dwarf.h"

#endif
EOF

cp "$backtracing_root"/modules/ImageFormats/Elf/*.h "$target_c_src/include/"
cp "$backtracing_root"/modules/ImageFormats/Dwarf/*.h "$target_c_src/include/"

swift_files=(
    ByteSwapping.swift
    Dwarf.swift
    Elf.swift
    Image.swift
    ImageSource.swift
    MemoryReader.swift
    Registers.swift
    Utils.swift
)

for f in "${swift_files[@]}"; do
    cp "$backtracing_root/$f" "$target_swift_src"
done
echo "$desc" > "$here/../Misc/vendored-backtracing_root.version"

vendored_file_text='//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Profile Recorder open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Profile Recorder project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Profile Recorder project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
// This file has been adjusted for ProfileRecorder, originally of the Swift.org open source project
'

find "$target_c_src" "$target_swift_src" \
    -type f \
    -exec gsed -ri \
        -e "s/\<Elf_/${prefix}_Elf_/g" \
        -e "s/\<Elf64_/${prefix}_Elf64_/g" \
        -e "s/\<Elf32_/${prefix}_Elf32_/g" \
        -e "s/\<Dwarf_/${prefix}_Dwarf_/g" \
        -e "s/import Swift//g" \
        -e "s/^let ELF64_/nonisolated(unsafe) let ELF64_/g" \
        -e "s/^let ELF32_/nonisolated(unsafe) let ELF32_/g" \
        -e "s/^let elf_/nonisolated(unsafe) let elf_/g" \
        -e "s/os\(linux\)/os(Linux)/g" \
        -e "s/internal import BacktracingImpl.ImageFormats.Dwarf/import CProfileRecorderSwiftELF/g" \
        -e "s/internal import BacktracingImpl.Runtime//g" \
        -e "s/internal import BacktracingImpl.ImageFormats.Elf/import CProfileRecorderSwiftELF/g" \
        -e "s/internal import BacktracingImpl.OS.Darwin//g" \
        -e "s/swift\.runtime\./CProfileRecorderSwiftELF./g" \
        -e "s/internal import/import/g" \
        -e "s/typealias SourceLocation = SymbolicatedBacktrace.SourceLocation//g" \
        -e "s/@_specialize\(kind: full, where R == RemoteMemoryReader\)//g" \
        -e "s/@_specialize\(kind: full, where R == MemserverMemoryReader\)//g" \
        -e "s/@_specialize\(kind: full, where R == RemoteMemoryReader, Traits == Elf32Traits\)//g" \
        -e "s/@_specialize\(kind: full, where R == RemoteMemoryReader, Traits == Elf64Traits\)//g" \
        -e "s/@_specialize\(kind: full, where R == MemserverMemoryReader, Traits == Elf32Traits\)//g" \
        -e "s/@_specialize\(kind: full, where R == MemserverMemoryReader, Traits == Elf64Traits\)//g" \
        -e "s/@_specialize\(kind: full, where R == UnsafeLocalMemoryReader\)//g" \
        -e "s/@_specialize\(kind: full, where R == UnsafeLocalMemoryReader, Traits == Elf32Traits\)//g" \
        -e "s/@_specialize\(kind: full, where R == UnsafeLocalMemoryReader, Traits == Elf64Traits\)//g" \
        -e "1s%^%$(echo "$vendored_file_text" | tr '\n' '%' | sed 's/%/\\n/g')%" \
        '{}' \;
echo "Okay, all done."
