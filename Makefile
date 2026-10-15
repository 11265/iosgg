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
ss_CFLAGS = -fobjc-arc \
            -IExternal/capstone \
            -IExternal/keystone \
            -IExternal/ptrscan/include \
            -ISources \
            -I.

# C++ 编译标志
ss_CXXFLAGS = -std=c++17

# 链接标志
ss_LDFLAGS = External/libcapstone.a \
            External/libkeystone.a \
            External/ptrscan/libptrscan-ios-arm64.a

# 源文件（显式声明，构建可追溯）
ss_FILES = \
    Sources/Tweak.x \
    \
    Sources/Constants/NotificationNames.m \
    \
    Sources/Models/AccessRecord.m \
    Sources/Models/AccessViewModel.m \
    Sources/Models/DisplayItem.m \
    Sources/Models/MemoryRegion.m \
    Sources/Models/ScanResult.m \
    \
    Sources/Services/Debugger/SSDebugger.mm \
    Sources/Services/Debugger/DynaDbg/debugger/exception_queue.mm \
    Sources/Services/TaskPortManager.m \
    \
    Sources/Services/Memory/AIAnalysisService.m \
    Sources/Services/Memory/ARM64Assembler.m \
    Sources/Services/Memory/InstructionBrowser.m \
    Sources/Services/Memory/PointerChainParser.m \
    Sources/Services/Memory/PointerScanner.mm \
    Sources/Services/Memory/PtrScanBridge.mm \
    \
    Sources/Services/MemoryProcessor.m \
    Sources/Services/ModuleViewer.m \
    Sources/Services/ProcessMemory.m \
    Sources/Services/LogService.mm \
    \
    Sources/Services/Remote/RemoteCallEngine.m \
    Sources/Services/Remote/MCPBridge.mm \
    \
    Sources/Services/Scanner/Scanner.mm \
    Sources/Services/Scanner/ScannerConfig.mm \
    Sources/Services/Scanner/ScannerState.m \
    Sources/Services/Scanner/SignatureScanner.m \
    Sources/Services/Scanner/SunScanner.m \
    \
    Sources/UI/Components/AccessCell.m \
    Sources/UI/Components/CyberButton.m \
    Sources/UI/Components/DraggableView.m \
    Sources/UI/Components/FloatingWindow.mm \
    Sources/UI/Components/MemoryCell.m \
    Sources/UI/Components/TerminalInputField.m \
    Sources/UI/Components/ThemeConfig.m \
    \
    Sources/UI/Dialogs/AddRecordDialog.m \
    Sources/UI/Dialogs/BaseAddressDialog.m \
    Sources/UI/Dialogs/CalculateOffsetDialog.m \
    Sources/UI/Dialogs/CompareDialog.m \
    Sources/UI/Dialogs/EditInstructionDialog.m \
    Sources/UI/Dialogs/EditValueDialog.m \
    Sources/UI/Dialogs/FileSelectionOverlay.m \
    Sources/UI/Dialogs/FilterSettingsOverlay.m \
    Sources/UI/Dialogs/FuzzySearchDialog.m \
    Sources/UI/Dialogs/GetSignatureDialog.m \
    Sources/UI/Dialogs/OffsetDialog.m \
    Sources/UI/Dialogs/OptionsMenu.m \
    Sources/UI/Dialogs/RegisterStateDialog.m \
    Sources/UI/Dialogs/SearchDialog.m \
    Sources/UI/Dialogs/SignatureDialog.m \
    \
    Sources/UI/Pages/AccessDetailViewController.m \
    Sources/UI/Pages/AccessPage.mm \
    Sources/UI/Pages/AccessRegisterViewController.m \
    Sources/UI/Pages/BreakpointHitPresenter.m \
    Sources/UI/Pages/FilterPage.mm \
    Sources/UI/Pages/MemoryPage.m \
    Sources/UI/Pages/MemoryPage+AssemblyActions.m \
    Sources/UI/Pages/MemoryPage+Batch.m \
    Sources/UI/Pages/ModulePage.m \
    Sources/UI/Pages/MorePage.mm \
    Sources/UI/Pages/OffsetCalcPage.m \
    Sources/UI/Pages/PointerScanPage.mm \
    Sources/UI/Pages/RecordPage.m \
    Sources/UI/Pages/RecordPage+Actions.m \
    Sources/UI/Pages/RemoteCallPage.m \
    Sources/UI/Pages/SearchPage.m \
    Sources/UI/Pages/SearchPage+Actions.m \
    Sources/UI/Pages/SettingsPage.mm \
    Sources/UI/Pages/SunScanPage.m \
    Sources/UI/Pages/TracePage.m \
    Sources/UI/Pages/TracePage+Debugger.m \
    \
    External/lz4/lz4.c \
    External/lz4/lz4file.c \
    External/lz4/lz4frame.c \
    External/lz4/lz4hc.c \
    External/lz4/xxhash.c


ss_FRAMEWORKS = UIKit

# Entitlements for task_for_pid access
ss_CODESIGN_FLAGS = -SEntitlements.plist

include $(THEOS_MAKE_PATH)/tweak.mk
