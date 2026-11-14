// SPDX-License-Identifier: GPL-2.0-or-later
// AppleScript, as AppleScript macros are written (layer 1). A light scanner of its own: compiling the script would
// be slow, could load application dictionaries, and would follow Script Editor's colors, not the theme's.
#import "TSSyntaxScanner.h"

NS_ASSUME_NONNULL_BEGIN

/// Comments (--, # and nested (* *)), strings with \" and \\, reserved words in any case, numbers and «raw events».
/// Text between vertical bars is an identifier and is not colored. Comments and strings may run over several lines, so
/// the whole text is scanned again after an edit.
NS_SWIFT_NAME(SyntaxAppleScriptScanner)
@interface TSSyntaxAppleScriptScanner : NSObject <TSSyntaxScanner>
/// Placeholders such as #FILEPATH#. A # that starts one of them does not start a comment.
@property (nonatomic, readonly, copy) NSArray<NSString *> *placeholders;
- (instancetype)initWithPlaceholders:(NSArray<NSString *> *)placeholders NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
