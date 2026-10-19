#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AccessRecord;

@protocol AccessCellDelegate <NSObject>
- (void)accessCellDidChangeEnabled:(BOOL)enabled forAddress:(uint64_t)address;
- (void)accessCellDidTapTypeForAddress:(uint64_t)address;
@end

@interface AccessCell : UITableViewCell

@property (nonatomic, weak, nullable) id<AccessCellDelegate> delegate;
@property (nonatomic, assign) uint64_t currentAddress;

+ (NSString *)reuseIdentifier;

- (void)configureWithRecord:(AccessRecord *)record;

/// 只刷新值/命中/最近时间/符号，不碰开关和类型控件（用于高频命中）
- (void)updateLiveValuesWithRecord:(AccessRecord *)record;

@end

NS_ASSUME_NONNULL_END
