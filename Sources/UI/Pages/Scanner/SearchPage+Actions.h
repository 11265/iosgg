#import "UI/Pages/Scanner/SearchPage.h"

NS_ASSUME_NONNULL_BEGIN

/// Button action handlers extracted from SearchPage to reduce file size.
@interface SearchPage (Actions)

- (void)searchTapped;
- (void)clearTapped;
- (void)blurTapped;
- (void)selectAllTapped;
- (void)invertSelectionTapped;
- (void)saveTapped;
- (void)helpTapped;
- (void)trackTapped;
- (void)signatureTapped;
- (void)offsetTapped;
- (void)calculateOffsetTapped;
- (void)modeSwitchChanged:(UISwitch *)sender;
- (void)accessoryButtonTapped:(UIButton *)sender;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)handleOffsetApplied:(NSNotification *)notification;

@end

NS_ASSUME_NONNULL_END
