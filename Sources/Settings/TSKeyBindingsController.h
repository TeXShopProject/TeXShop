// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
// The key binding list in Settings › Keyboard. Each change is written to
// autocompletion.plist and autocompletionDisplayOrder.plist at once and takes
// effect in open documents; Edit › Undo restores the previous list.
//
// Output strings keep their file format. In the table, #SEL#, #INS#, #PASTE#
// and • are shown as tokens; Insert adds them and the help button lists them.
@interface TSKeyBindingsController : NSViewController
@property (readonly) NSTableView *tableView;
@property (readonly) NSPopUpButton *insertButton;
@property (readonly) NSButton *symbolsButton;
// The output strings as written to the file, in display order.
@property (readonly) NSArray<NSString *> *keys;
@property (readonly) NSArray<NSString *> *values;
- (void)reloadFromGlobalData;
- (IBAction)add:(nullable id)sender;
- (IBAction)delete:(nullable id)sender;
- (IBAction)insertSymbol:(nullable id)sender;
- (IBAction)showSymbols:(nullable id)sender;
// The view shown by the help button; also used for screenshots.
- (NSView *)makeSymbolListView;
// Tokens for symbols, and the file text for tokens.
+ (NSAttributedString *)displayStringForOutput:(NSString *)output font:(NSFont *)font;
+ (NSString *)outputForDisplayString:(NSAttributedString *)text;
@end
NS_ASSUME_NONNULL_END
