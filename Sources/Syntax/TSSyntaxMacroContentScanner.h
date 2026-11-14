// SPDX-License-Identifier: GPL-2.0-or-later
// The contents of a macro (layer 1): TeX or AppleScript, as the macro is run, with its placeholders on top.
#import "TSSyntaxScanner.h"
#import "TSSyntaxTeXOptions.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(SyntaxMacroContentScanner)
@interface TSSyntaxMacroContentScanner : NSObject <TSSyntaxScanner>
/// The placeholders that a TeX macro replaces, in the order they are replaced: #SEL#, #PASTE#, #INS# (the first one only).
@property (class, nonatomic, readonly, copy) NSArray<NSString *> *teXPlaceholders;
/// The placeholders that an AppleScript macro replaces, in the order they are replaced: #FILEPATH# and the others.
@property (class, nonatomic, readonly, copy) NSArray<NSString *> *appleScriptPlaceholders;
/// What the macro editor shows as tokens, in order: in a TeX macro the placeholders it replaces (#SEL#, #PASTE#, the
/// first #INS#) and the bullet of each mark (the note of •‹note› stays text); in an AppleScript macro #FILEPATH# and
/// the others. The same occurrences that are colored as placeholders.
+ (void)enumerateTokensInString:(NSString *)string usingBlock:(NS_NOESCAPE void (^)(NSRange range, NSString *symbol))block;
@property (nonatomic, readonly, copy) TSSyntaxTeXOptions *teXOptions;
/// The contents of a TeX macro are scanned as the source is, with these options.
- (instancetype)initWithTeXOptions:(TSSyntaxTeXOptions *)teXOptions NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
