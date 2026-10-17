#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 反汇编列表的一行（由 AccessHitInspectorViewController 构建）。
@interface SSDisassemblyLine : NSObject

@property (nonatomic, assign) uint64_t address;
@property (nonatomic, copy) NSString *bytesText;
@property (nonatomic, copy) NSString *mnemonic;
@property (nonatomic, copy) NSString *operands;
@property (nonatomic, copy, nullable) NSString *annotation;
@property (nonatomic, assign) BOOL isCurrent;
@property (nonatomic, assign) BOOL isBranch;
@property (nonatomic, assign) uint64_t branchTarget;

@end

@interface SSDisassemblyCell : UITableViewCell

+ (NSString *)reuseIdentifier;

- (void)configureWithLine:(SSDisassemblyLine *)line;

@end

NS_ASSUME_NONNULL_END
