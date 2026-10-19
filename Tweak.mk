export THEOS_DEVICE_IP = 192.168.3.12
ARCHS = arm64
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = pvz#结束进程
THEOS_PACKAGE_SCHEME = rootless#多巴胺支持

# 确保 SDK 路径正确
SDK_PATH = $(THEOS)/sdks/iPhoneOS.sdk

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ss

# 顶层构建入口是根目录 Makefile；本文件只描述 Objective-C / ObjC++ UI 与适配层。
# C++17 核心已由 Core/Makefile 独立编译为静态库，这里只负责链接。
CORE_LIB ?= $(CURDIR)/build/libsscore.a

# 编译标志
# 注意：Theos 不带 FINALPACKAGE=1 时默认 DEBUG=1 → -O0（包名带 +debug）。
# 性能相关的包请用：  make package FINALPACKAGE=1
# 下面显式 -O2 覆盖 release 的 -Os：扫描/比较/LZ4 循环对优化等级很敏感。
#
# 分层约定（重构后）：
#   Sources/UI/**/*.m         纯 Objective-C（不允许 .mm / C++）
#   Sources/Core/Algorithms/*.cpp 纯 C++17 核心算法（已独立编译为 build/libsscore.a）
#   Sources/Modules/**        Objective-C / Objective-C++ 适配层
# 主机侧核心测试： ./Tests/run_tests.sh
# 分层约束检查：   ./scripts/check_layering.sh
ss_CFLAGS = -fobjc-arc \
            -IExternal/capstone \
            -IExternal/keystone \
            -IExternal/ptrscan/include \
            -IExternal/ptrscan/include/format \
            -IExternal/ptrscan/include/vma \
            -IExternal/ptrscan/include/platform \
            -ISources \
            -I. \
            -fno-common \
            -O2

# C++ 编译标志（适配层里的 C++/ObjC++ 仍使用 C++17）
ss_CXXFLAGS = -std=c++17 -O2

# 链接标志：核心静态库 + 外部引擎
# PtrScan 已改为直接编译 External/ptrscan/src 源码，不再链接预编译
# libptrscan.a，也不再构建 CLI。
ss_LDFLAGS = $(CORE_LIB) \
            External/libcapstone.a \
            External/libkeystone.a \
            -lz

# 源文件（自动发现；DynaDbg 与 PtrScan 的显式列表放在各自模块的 .mk 中）
# 注意：Sources/Core/Algorithms/*.cpp 由 Core/Makefile 独立编译，不能在这里重复编译
ss_FILES = $(shell find Sources -type f \( -name '*.m' -o -name '*.mm' -o -name '*.x' -o -name '*.c' -o -name '*.cpp' \) \
    ! -path 'Sources/Modules/Debugger/DynaDbg/*' \
    ! -path 'Sources/Core/Algorithms/*')

# DynaDbg：每个实现文件独立编译
include Sources/Modules/Debugger/DynaDbg/DynaDbg.mk
ss_FILES += $(DYNADBG_SRC)

# PtrScan：源码 in-process，无 CLI / 无 public API
include External/ptrscan/ptrscan.mk
ss_FILES += $(PTRSCAN_SRC)

ss_FILES += $(wildcard External/lz4/*.c)

ss_FRAMEWORKS = UIKit


include $(THEOS_MAKE_PATH)/tweak.mk
