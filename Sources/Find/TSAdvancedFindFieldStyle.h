// SPDX-License-Identifier: GPL-2.0-or-later
// How the Advanced Find panel's find and replace fields and the find and replacement cells of the multiple
// replacement rules look: the source's theme, font and TeX settings. The application gives them through `provider`;
// the files of the panel read no preferences and no themes themselves.
#import <AppKit/AppKit.h>
#import "TSSyntaxColorScheme.h"
#import "TSSyntaxTeXOptions.h"

NS_ASSUME_NONNULL_BEGIN

/// Posted (by +styleDidChange) when the theme, the font or the settings of syntax coloring have changed.
FOUNDATION_EXPORT NSNotificationName const TSAdvancedFindFieldStyleDidChangeNotification;

/// YES for a dark appearance (Dark Aqua and its variants).
FOUNDATION_EXPORT BOOL TSAdvancedFindAppearanceIsDark(NSAppearance *appearance) NS_SWIFT_NAME(AdvancedFindAppearanceIsDark(_:));

NS_SWIFT_NAME(AdvancedFindFieldStyle)
@interface TSAdvancedFindFieldStyle : NSObject

/// `scheme`: the theme's colors of the syntax roles, nil when syntax coloring is off. A nil font or color leaves the
/// panel's own.
- (instancetype)initWithScheme:(nullable TSSyntaxColorScheme *)scheme texOptions:(TSSyntaxTeXOptions *)texOptions font:(nullable NSFont *)font
                     textColor:(nullable NSColor *)textColor backgroundColor:(nullable NSColor *)backgroundColor
           insertionPointColor:(nullable NSColor *)insertionPointColor NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly, nullable) TSSyntaxColorScheme *scheme;
/// How text is read with "Regular expression" off: as the source reads TeX.
@property (nonatomic, readonly, copy) TSSyntaxTeXOptions *texOptions;
@property (nonatomic, readonly, nullable) NSFont *font;
@property (nonatomic, readonly, nullable) NSColor *textColor;
@property (nonatomic, readonly, nullable) NSColor *backgroundColor;
@property (nonatomic, readonly, nullable) NSColor *insertionPointColor;

/// The colors of the fields: those of `scheme` (none without it), and the marks of errors (red, underlined) and of
/// what OgreKit reads otherwise (orange, a dotted line), which are not theme colors.
@property (nonatomic, readonly) TSSyntaxColorScheme *fieldScheme;
/// The font of the panel's fields: the system's monospaced font, at the size of the source font kept between 11
/// and 16 points, so that the panel keeps its layout, or at 14 points without a source font.
@property (nonatomic, readonly) NSFont *fieldFont;
/// The appearance that matches `backgroundColor` (nil without one): the field's buttons, its status and the marks
/// take the colors of a light or a dark background.
@property (nonatomic, readonly, nullable) NSAppearance *fieldAppearance;

/// What the application gives for a light or a dark window. Without it, the fields look like other text fields.
@property (class, nonatomic, copy, nullable) TSAdvancedFindFieldStyle *_Nullable (^provider)(BOOL dark);
/// The style for a window of `appearance`.
+ (TSAdvancedFindFieldStyle *)styleForAppearance:(NSAppearance *)appearance;
/// The style for `window`: its own appearance, or the application's, which it follows. (The window's effective
/// appearance can lag behind the application's while the application's change is being observed.)
+ (TSAdvancedFindFieldStyle *)styleForWindow:(nullable NSWindow *)window;
/// The application calls this when the theme, the font or the settings of syntax coloring change.
+ (void)styleDidChange;

@end

NS_ASSUME_NONNULL_END
