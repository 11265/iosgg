#!/usr/bin/env bash
# 编译并运行纯 C++17 核心的主机侧回归测试。
set -euo pipefail

cd "$(dirname "$0")/.."

CXX="${CXX:-g++}"
OUT="${TMPDIR:-/tmp}/iosgg_core_tests"

"$CXX" -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter -I Sources \
    Tests/CoreEngineTests.cpp \
    Sources/Core/Algorithms/SSScanCore.cpp \
    Sources/Core/Algorithms/SSSignatureCore.cpp \
    Sources/Core/Algorithms/SSPointerChainCore.cpp \
    -o "$OUT"

"$OUT"
