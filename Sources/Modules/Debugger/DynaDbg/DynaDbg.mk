# DynaDbg 独立编译单元清单。
#
# 自动发现时排除了整个 DynaDbg 目录；这里显式列出所有实现文件，避免
# SSDebugger.mm 再通过 #include 合并编译。exception_queue.mm 也在这里。
#
# 注意：callback_stubs.mm / memory_io.mm 仍不参与编译（按上游引用关系
# 确认后再决定），不要因为它们在目录里就自动加入。

DYNADBG_DIR ?= Sources/Modules/Debugger/DynaDbg

DYNADBG_SRC := \
    $(DYNADBG_DIR)/debugger/debugger_native_api.mm \
    $(DYNADBG_DIR)/debugger/debugger_core.mm \
    $(DYNADBG_DIR)/debugger/debugger_watchpoint.mm \
    $(DYNADBG_DIR)/debugger/debugger_breakpoint.mm \
    $(DYNADBG_DIR)/debugger/debugger_exception.mm \
    $(DYNADBG_DIR)/debugger/debugger_trace.mm \
    $(DYNADBG_DIR)/debugger/debugger_register.mm \
    $(DYNADBG_DIR)/debugger/debugger_unwind.mm \
    $(DYNADBG_DIR)/core/native_api.mm \
    $(DYNADBG_DIR)/core/process_api.mm \
    $(DYNADBG_DIR)/core/file_api.mm \
    $(DYNADBG_DIR)/common/util.cpp \
    $(DYNADBG_DIR)/common/trace_file.cpp \
    $(DYNADBG_DIR)/common/arm64_decoder.cpp \
    $(DYNADBG_DIR)/debugger/exception_queue.mm
