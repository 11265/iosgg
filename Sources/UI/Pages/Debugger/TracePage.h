#import <UIKit/UIKit.h>
#import "Modules/Debugger/SSDebugger.h"

NS_ASSUME_NONNULL_BEGIN

@interface SSTrackRecord : NSObject
@property (nonatomic, assign) uint64_t address;      // 监视地址
@property (nonatomic, assign) uint64_t value;        // 当前值
@property (nonatomic, assign) uint64_t instructionAddr;  // 触发指令地址
@property (nonatomic, assign) SSBreakpointType type; // 触发类型
@property (nonatomic, strong, nonnull) NSDate *timestamp;     // 触发时间
@property (nonatomic, assign) NSInteger hitCount;    // 添加触发计数
@end

@interface SSTrackPopViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, strong, readonly) NSMutableArray<SSTrackRecord *> *trackingData;
@property (nonatomic, strong, readonly) NSMutableArray<NSNumber *> *watchAddresses;
@property (nonatomic, assign, readonly) BOOL isDebugging;

+ (instancetype)trackPopViewController;

// 显示/隐藏方法
- (void)show;

@end

NS_ASSUME_NONNULL_END 