#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Overlay view for selecting scan result files.
@interface FileSelectionOverlay : UIView

@property (nonatomic, copy, nullable) void (^onFileSelected)(NSString *path);
@property (nonatomic, copy, nullable) void (^onFileDeleted)(NSString *path);
@property (nonatomic, copy, nullable) void (^onClose)(void);

@end

NS_ASSUME_NONNULL_END
