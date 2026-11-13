// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import "TSRegexReplacementTemplate.h"

NS_ASSUME_NONNULL_BEGIN

/// The regular expression cheat sheet, shown from the "?" next to "Regular expression" in a popover that can be
/// dragged off as a window, as in CotEditor. Three pages under small tabs, each in the same room so the popover keeps
/// its size: the everyday syntax in two columns, the replacement syntax that is selected, and the differences from
/// OgreKit from the engine's one table (+[TSRegexFindPattern onigmoIncompatibilities]). Below them, a link to ICU's
/// user guide. Small text throughout.
NS_SWIFT_NAME(AdvancedFindCheatSheet)
@interface TSAdvancedFindCheatSheet : NSViewController

- (instancetype)initWithReplacementSyntax:(TSRegexReplacementSyntax)syntax NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

/// Rebuilds the replacement part for another syntax (the setting changed while the sheet is open).
@property (nonatomic) TSRegexReplacementSyntax replacementSyntax;
/// 0 Find (the everyday syntax), 1 Replace (the selected syntax), 2 Differences from OgreKit; 0 when opened.
@property (nonatomic, readonly) NSInteger selectedPage;
- (void)selectPage:(NSInteger)index;
/// The terms of every page, in order (for the tests).
@property (nonatomic, readonly, copy) NSArray<NSString *> *terms;

/// Measures the sheet again (when shown, and for the images after an appearance is set) and sets preferredContentSize.
- (void)fitToContent;

/// ICU's user guide on regular expressions.
@property (class, nonatomic, readonly) NSURL *icuGuideURL;

@end

NS_ASSUME_NONNULL_END
