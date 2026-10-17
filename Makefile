export THEOS_DEVICE_IP = 192.168.3.12
ARCHS = arm64
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = pvz#结束进程
THEOS_PACKAGE_SCHEME = rootless#多巴胺支持

# 确保 SDK 路径正确
SDK_PATH = $(THEOS)/sdks/iPhoneOS.sdk

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ss

# 编译标志
# 注意：Theos 不带 FINALPACKAGE=1 时默认 DEBUG=1 → -O0（包名带 +debug）。
# 性能相关的包请用：  make package FINALPACKAGE=1
# 下面显式 -O2 覆盖 release 的 -Os：扫描/比较/LZ4 循环对优化等级很敏感。
ss_CFLAGS = -fobjc-arc \
            -IExternal/capstone \
            -IExternal/keystone \
            -IExternal/ptrscan/include \
            -ISources \
            -I. \
            -O2

# C++ 编译标志
ss_CXXFLAGS = -std=c++17

# 链接标志
ss_LDFLAGS = External/libcapstone.a \
            External/libkeystone.a \
            External/ptrscan/libptrscan-ios-arm64.a

# 源文件（自动发现，新增模块/文件无需修改 Makefile）
# 注意：DynaDbg/ 下的 .mm/.cpp 被 SSDebugger.mm 直接 #include，不单独编译
#       唯一例外是 exception_queue.mm（独立编译单元）
ss_FILES = $(shell find Sources -type f \( -name '*.m' -o -name '*.mm' -o -name '*.x' -o -name '*.c' -o -name '*.cpp' \) \
    ! -path 'Sources/Modules/Debugger/DynaDbg/*')
ss_FILES += Sources/Modules/Debugger/DynaDbg/debugger/exception_queue.mm
ss_FILES += $(wildcard External/lz4/*.c)


ss_FRAMEWORKS = UIKit


include $(THEOS_MAKE_PATH)/tweak.mk
