// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAdvancedFindTask;

/// The sheet of a long task, as CotEditor's: its title, a progress bar with Cancel as an × to its right (Escape),
/// and a short message under the bar, all in the small size.
/// It reads the task's progress and message ten times a second.
NS_SWIFT_NAME(AdvancedFindProgressSheet)
@interface TSAdvancedFindProgressSheet : NSObject

- (instancetype)initWithTask:(TSAdvancedFindTask *)task NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) NSProgressIndicator *progressBar;
@property (nonatomic, readonly) NSTextField *messageField;
@property (nonatomic, readonly) NSButton *cancelButton;

- (void)beginOnWindow:(NSWindow *)window;
- (void)end;
/// Reads the task's progress and message now (the timer does it while the sheet is shown).
- (void)update;

@end

NS_ASSUME_NONNULL_END
