// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
// Whole-percentage opacity input (0–100). Refused input calls rejectionHandler,
// which beeps by default.
@interface TSOpacityFormatter : NSFormatter
@property (nonatomic, copy, nullable) void (^rejectionHandler)(void);
+ (nullable NSString *)normalizedDigits:(NSString *)string;
@end
@interface TSSettingsLabel : NSTextField
@property (nonatomic, strong) NSColor *enabledTextColor;
@end
@interface TSSettingsIconView : NSView
- (instancetype)initWithSymbolName:(NSString *)symbolName color:(NSColor *)color size:(CGFloat)size;
@end
@interface TSSettingsGroupView : NSView
@property (copy) NSString *title;
@property (strong, readonly) NSView *contentView;
@end
@interface TSSettingsGroupStyle : NSObject
+ (CGFloat)cornerRadiusForMajorVersion:(NSInteger)version;
+ (void)applyToBox:(NSBox *)box;
@end
@interface TSSettingsControlRow : NSObject
@property (copy, readonly) NSArray<NSView *> *controls;
@property (readonly) NSUInteger indentation;
- (instancetype)initWithControls:(NSArray<NSView *> *)controls indentation:(NSUInteger)indentation NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end
@interface TSPrefPaneLayout : NSObject
+ (NSView *)opacityForColorWell:(NSColorWell *)well;
+ (NSView *)stepperForIntegerField:(NSTextField *)field;
+ (NSView *)switchForButton:(NSButton *)button;
+ (NSView *)choiceForControls:(NSArray<NSView *> *)controls;
+ (NSView *)catalogRowWithTitle:(NSString *)title note:(NSString *)note accessory:(NSView *)accessory expands:(BOOL)expands indent:(NSUInteger)indent;
+ (NSView *)catalogContent:(NSView *)content trailing:(BOOL)trailing indent:(NSUInteger)indent;
+ (NSView *)viewForRow:(TSSettingsControlRow *)row;
+ (NSView *)categoryHeaderWithTitle:(NSString *)title summary:(NSString *)summary symbol:(NSString *)symbol color:(NSColor *)color;
+ (void)decorateGroupsInView:(NSView *)view;
+ (void)arrangeView:(NSView *)view;
+ (void)attachRows:(NSArray<NSView *> *)rows toView:(NSView *)view;
+ (void)prepareControl:(NSView *)view;
+ (NSStackView *)stackWithViews:(NSArray<NSView *> *)views orientation:(NSUserInterfaceLayoutOrientation)orientation;
// The yellow warning triangle used beside settings warnings, sized for font.
+ (NSImageView *)warningSymbolForFont:(NSFont *)font;
@end
NS_ASSUME_NONNULL_END
