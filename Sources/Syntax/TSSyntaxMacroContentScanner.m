// SPDX-License-Identifier: GPL-2.0-or-later
#import "TSSyntaxMacroContentScanner.h"
#import "TSSyntaxTeXScanner.h"
#import "TSSyntaxAppleScriptScanner.h"
#import "TSMacroContentKind.h"

@implementation TSSyntaxMacroContentScanner

+ (NSArray<NSString *> *)teXPlaceholders
{
    // -[TSDocument insertSpecial:undoKey:] replaces them in this order, and #INS# only once: it marks where the
    // insertion point goes.
    return @[@"#SEL#", @"#PASTE#", @"#INS#"];
}

+ (NSArray<NSString *> *)appleScriptPlaceholders
{
    // -[TSMacroMenuController doMacro:] replaces them in this order.
    return @[@"#FILEPATH#", @"#PDFPATH#", @"#DVIPATH#", @"#PSPATH#", @"#LOGPATH#", @"#AUXPATH#", @"#INDPATH#", @"#BBLPATH#",
             @"#HTMLPATH#", @"#NAMEPATH#", @"#TEXPATH#", @"#DOCUMENTNAME#", @"#FOLDERPATH#"];
}

- (instancetype)initWithTeXOptions:(TSSyntaxTeXOptions *)teXOptions
{
    if ((self = [super init]))
        _teXOptions = [teXOptions copy];
    return self;
}

- (NSRange)lineAlignedRangeForEditedRange:(NSRange)range inString:(NSString *)string
{
    // The kind of a macro depends on its first line, and AppleScript has comments and strings over several lines.
    return NSMakeRange(0, string.length);
}

// Marks: • alone, and •‹note›, whose note runs to the next ›.
static void TSEnumerateMarks(NSString *string, NSRange range, NS_NOESCAPE TSSyntaxTokenBlock block)
{
    NSUInteger location = range.location;
    while (location < NSMaxRange(range)) {
        NSRange bullet = [string rangeOfString:@"•" options:NSLiteralSearch range:NSMakeRange(location, NSMaxRange(range) - location)];
        if (bullet.location == NSNotFound)
            return;
        NSUInteger end = NSMaxRange(bullet);
        if (end < NSMaxRange(range) && [string characterAtIndex:end] == 0x2039) {
            NSRange close = [string rangeOfString:@"›" options:NSLiteralSearch range:NSMakeRange(end, NSMaxRange(range) - end)];
            if (close.location != NSNotFound)
                end = NSMaxRange(close);
        }
        block(NSMakeRange(bullet.location, end - bullet.location), TSSyntaxRoleMark, TSSyntaxTokenFlagsNone);
        location = end;
    }
}

// Placeholders are replaced as plain text, in comments and strings too, so they are colored over everything else.
// They are replaced one name after another; an occurrence that shares characters with one replaced before it is gone
// by the time its turn comes, and is not colored. A name in `once` is replaced the first time only (#INS#).
static void TSEnumeratePlaceholders(NSString *string, NSRange range, NSArray<NSString *> *placeholders, NSSet<NSString *> *once,
                                    NS_NOESCAPE TSSyntaxTokenBlock block)
{
    NSMutableIndexSet *taken = [NSMutableIndexSet indexSet];
    NSMutableArray<NSValue *> *found = [NSMutableArray array];
    for (NSString *placeholder in placeholders) {
        NSUInteger location = range.location;
        while (location < NSMaxRange(range)) {
            NSRange match = [string rangeOfString:placeholder options:NSLiteralSearch range:NSMakeRange(location, NSMaxRange(range) - location)];
            if (match.location == NSNotFound)
                break;
            if (![taken intersectsIndexesInRange:match]) {
                [taken addIndexesInRange:match];
                [found addObject:[NSValue valueWithRange:match]];
                if ([once containsObject:placeholder])
                    break;
            }
            location = NSMaxRange(match);
        }
    }
    [found sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        return a.rangeValue.location < b.rangeValue.location ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (NSValue *match in found)
        block(match.rangeValue, TSSyntaxRolePlaceholder, TSSyntaxTokenFlagsNone);
}

- (void)enumerateTokensInString:(NSString *)string range:(NSRange)range usingBlock:(NS_NOESCAPE TSSyntaxTokenBlock)block
{
    if (TSMacroContentKindForString(string) == TSMacroContentKindTeX) {
        [[[TSSyntaxTeXScanner alloc] initWithOptions:self.teXOptions] enumerateTokensInString:string range:range usingBlock:block];
        TSEnumerateMarks(string, range, block);
        TSEnumeratePlaceholders(string, range, TSSyntaxMacroContentScanner.teXPlaceholders, [NSSet setWithObject:@"#INS#"], block);
    } else {
        NSArray<NSString *> *placeholders = TSSyntaxMacroContentScanner.appleScriptPlaceholders;
        [[[TSSyntaxAppleScriptScanner alloc] initWithPlaceholders:placeholders] enumerateTokensInString:string range:range usingBlock:block];
        TSEnumeratePlaceholders(string, range, placeholders, [NSSet set], block);
    }
}

@end
