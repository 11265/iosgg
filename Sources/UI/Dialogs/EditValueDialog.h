#import <UIKit/UIKit.h>

// 引入搜索数据类型枚举
#import "Services/Scanner/Scanner.h"

// 声明通知常量
extern NSString *const kModifyValueNotification;

@interface SSModifyPopViewController : UIViewController

@property (nonatomic, assign) uint64_t address;  // 要修改的地址
@property (nonatomic, assign) SearchDataType dataType; // 修改为 SearchDataType 类型
@property (nonatomic, copy) NSString *initialValue;  // 用于存储初始值

+ (instancetype)modifyPopViewController;

@end 