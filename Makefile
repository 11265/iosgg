# 顶层构建入口：C++17 核心与 Objective-C UI 分开编译，最后链接。
#
#   make                    先编译 Build/Core/ 下的 C++17 静态库，再编译 UI/tweak
#   make package            同上，然后打包
#   make clean              清理两边产物
#
# 需要 THEOS 指向 Theos；未设置时默认 ~/theos。
# C++ 核心产物：build/libsscore.a
# Theos 构建文件：Tweak.mk（只包含 ObjC/ObjC++ 源，链接上面的静态库）

THEOS ?= $(HOME)/theos
export THEOS

CORE_DIR       := $(CURDIR)/Build/Core
CORE_LIB       := $(CURDIR)/build/libsscore.a
TWEAK_MAKEFILE := Tweak.mk

# 让 FINALPACKAGE 同时作用于核心与 tweak，保证 print-archive 的路径一致
CORE_FLAGS := FINALPACKAGE=$(FINALPACKAGE)

.PHONY: all core tweak clean package install do stage

all: tweak

# 第一阶段：纯 C++17 核心，独立编译成静态库
core:
	@$(MAKE) -C "$(CORE_DIR)" THEOS="$(THEOS)" $(CORE_FLAGS)
	@mkdir -p "$(dir $(CORE_LIB))"
	@archive="$$($(MAKE) -C "$(CORE_DIR)" -s print-archive THEOS="$(THEOS)" $(CORE_FLAGS))"; \
	 cp "$$archive" "$(CORE_LIB)"; \
	 echo "C++ core archive: $(CORE_LIB)"

# 第二阶段：Objective-C / ObjC++ UI 与适配层，链接第一阶段产物
tweak: core
	@$(MAKE) -f "$(TWEAK_MAKEFILE)" CORE_LIB="$(CORE_LIB)" THEOS="$(THEOS)" $(CORE_FLAGS)

clean:
	@$(MAKE) -C "$(CORE_DIR)" clean THEOS="$(THEOS)" || true
	@$(MAKE) -f "$(TWEAK_MAKEFILE)" clean THEOS="$(THEOS)" || true
	@rm -rf "$(CURDIR)/build"

# package / install / do / stage：先保证核心已构建，再转发给 Tweak.mk
package install do stage: core
	@$(MAKE) -f "$(TWEAK_MAKEFILE)" $@ CORE_LIB="$(CORE_LIB)" THEOS="$(THEOS)" $(CORE_FLAGS)
