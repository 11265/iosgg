#import "UI/Pages/Memory/MemoryPage.h"
#import "UI/Dialogs/GetSignatureDialog.h"
#import "UI/Dialogs/CalculateOffsetDialog.h"
#import "UI/Dialogs/EditInstructionDialog.h"

NS_ASSUME_NONNULL_BEGIN

/// Assembly-level operations extracted from MemoryPages to reduce file size.
@interface MemoryPages (AssemblyActions) <SSInstructionEditViewDelegate, SSPatternLengthViewDelegate, SSPatternResultViewDelegate, SSOffsetCalculatorViewDelegate, SSOffsetResultViewDelegate>

- (void)handleAIAnalysis:(uint64_t)address instruction:(uint32_t)instruction disassembly:(NSString *)disassembly;
- (void)handleGeneratePattern:(uint64_t)address instruction:(uint32_t)instruction disassembly:(NSString *)disassembly;
- (void)handleCalculateOffset:(uint64_t)address;
- (void)addExecuteBreakpoint:(uint64_t)address software:(BOOL)software stopExecution:(BOOL)stopExecution;
- (void)removeExecuteBreakpoint:(uint64_t)address;
- (void)showAPIKeyConfigDialog;
- (uint64_t)getModuleBaseAddress:(NSString *)moduleName;
- (uint32_t)assembleInstruction:(NSString *)instructionStr atAddress:(uint64_t)address;
- (NSString *)generatePattern:(uint32_t)instruction withDisassembly:(NSString *)disassembly atAddress:(uint64_t)address;

@end

NS_ASSUME_NONNULL_END
