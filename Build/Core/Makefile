# C++17 核心的独立构建目标（静态库）。
#
# 只编译 Sources/Core/Algorithms 下的纯 C++17 算法，不包含任何 ObjC/UI 源文件；
# 产物为 sscore.a，由根目录 Makefile 复制到 build/libsscore.a 后交给 tweak 链接。
#
# 单独构建：
#   THEOS=$HOME/theos make -C Build/Core
# 清理：
#   THEOS=$HOME/theos make -C Build/Core clean

export THEOS_DEVICE_IP = 192.168.3.12
ARCHS = arm64
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = sscore

# 静态库：不安装、不打包，只作为 tweak 的链接输入
sscore_LINKAGE_TYPE = static
sscore_INSTALL = 0

# 只包含纯 C++17 核心；UI / 适配层一律不进来
sscore_FILES = $(wildcard ../../Sources/Core/Algorithms/*.cpp)

sscore_CFLAGS = -I../../Sources -I../.. -O2
sscore_CXXFLAGS = -std=c++17 -O2

include $(THEOS_MAKE_PATH)/library.mk

# 供根目录 Makefile 查询静态库的最终路径（debug/release 路径不同）
.PHONY: print-archive
print-archive:
	@echo $(THEOS_OBJ_DIR)/sscore.a
