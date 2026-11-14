// SPDX-License-Identifier: GPL-2.0-or-later
// The colors of syntax coloring, made from a theme: roles to display attributes. Depends on AppKit colors only,
// not on a document or a view.
#import <AppKit/AppKit.h>
#import "TSSyntaxRole.h"

NS_ASSUME_NONNULL_BEGIN

/// Immutable. Every attribute dictionary is made once, so that whoever applies them can tell its own values from
/// those of other features by identity.
NS_SWIFT_NAME(SyntaxColorScheme)
@interface TSSyntaxColorScheme : NSObject <NSCopying>

/// The colors of a theme (a dictionary of Themes/*.plist) in a light or a dark window. A color the theme does not
/// define comes from another key or from the built-in color of the mode, as each role has always done.
- (instancetype)initWithTheme:(NSDictionary<NSString *, id> *)theme dark:(BOOL)dark;
- (instancetype)initWithAttributes:(NSDictionary<NSNumber *, NSDictionary<NSAttributedStringKey, id> *> *)attributes
                activeLineAttributes:(NSDictionary<NSAttributedStringKey, id> *)activeLineAttributes
           braceHighlightAttributes:(NSDictionary<NSAttributedStringKey, id> *)braceHighlightAttributes
         contentHighlightAttributes:(NSDictionary<NSAttributedStringKey, id> *)contentHighlightAttributes NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Only attributes that temporary attributes can show: colors and underlines. Empty when the role is shown as plain
/// text, as the marks of errors and incompatibilities are (their colors are the find panel's), or when the theme has
/// no color for it.
- (NSDictionary<NSAttributedStringKey, id> *)attributesForRole:(TSSyntaxRole)role;
/// The background of the line holding the insertion point.
@property (nonatomic, readonly, copy) NSDictionary<NSAttributedStringKey, id> *activeLineAttributes;
/// The matching brace, and the text between two braces.
@property (nonatomic, readonly, copy) NSDictionary<NSAttributedStringKey, id> *braceHighlightAttributes;
@property (nonatomic, readonly, copy) NSDictionary<NSAttributedStringKey, id> *contentHighlightAttributes;

@end

NS_ASSUME_NONNULL_END
