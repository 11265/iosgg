# PtrScan 源码选择（来自 External/ptrscan，upstream fast_ptrscan）。
#
# 只编译 portable core + Apple platform 后端：
#   - 不编译 main.c（CLI）
#   - 不编译 api.c（public ptrscan_* API）
#   - 不编译 Linux 的 maps_linux.c / mem_linux.c
#
# 由 Tweak.mk include，路径相对于仓库根目录。

PTRSCAN_DIR ?= External/ptrscan

PTRSCAN_SRC := \
    $(PTRSCAN_DIR)/src/pc_list.c \
    $(PTRSCAN_DIR)/src/ptr_index.c \
    $(PTRSCAN_DIR)/src/spill.c \
    $(PTRSCAN_DIR)/src/fs_ptrscan.c \
    $(PTRSCAN_DIR)/src/format/txt.c \
    $(PTRSCAN_DIR)/src/format/idx.c \
    $(PTRSCAN_DIR)/src/format/pcf.c \
    $(PTRSCAN_DIR)/src/vma/vma_map.c \
    $(PTRSCAN_DIR)/src/vma/vm_area.c \
    $(PTRSCAN_DIR)/src/vma/vma_select.c \
    $(PTRSCAN_DIR)/src/vma/image.c \
    $(PTRSCAN_DIR)/src/vma/image_probe.c \
    $(PTRSCAN_DIR)/src/platform/mach_common.c \
    $(PTRSCAN_DIR)/src/platform/maps_apple.c \
    $(PTRSCAN_DIR)/src/platform/mem_apple.c
