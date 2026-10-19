/*
 * ============================================================================
 *  指针链扫描（pointer chain scan）—— 本节代码标识
 *    ID      : 0CA2-4AD8-8E17-C3746067D85A
 *    日期时间: 2026-10-16 02:40:18
 *    引擎    : External/ptrscan/src（fast_ptrscan 源码，in-process）
 *    说明    : 区域枚举/索引/扫描/结果导出都在这里，UI 在 PointerScanPage，
 *              结果查看与两次对比在 FilterPage。
 * ============================================================================
 */

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FilterPage : UIViewController

/*
 * 指针扫描页把结果文件直接传进来：打开这个页面就自动加载、校验、算好
 * 每条的最终地址与当前值，不用再去文件选择里手动挑。
 */
@property (nonatomic, copy, nullable) NSString *initialFilePath;

@end

NS_ASSUME_NONNULL_END
