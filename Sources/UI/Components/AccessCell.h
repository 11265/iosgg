#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AccessRecord;

@protocol AccessCellDelegate <NSObject>
- (void)accessCellDidChangeEnabled:(BOOL)enabled forAddress:(uint64_t)address;
- (void)accessCellDidChangeType:(NSInteger)type forAddress:(uint64_t)address;
@end

@interface AccessCell : UITableViewCell

@property (nonatomic, weak) id<AccessCellDelegate> delegate;
@property (nonatomic, assign) uint64_t currentAddress;

+ (NSString *)reuseIdentifier;

- (void)configureWithRecord:(AccessRecord *)record;

@end

NS_ASSUME_NONNULL_END
