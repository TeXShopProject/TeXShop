// The macro editor shows the placeholders of a macro as tokens, as the key binding list does: the occurrences the
// macro replaces, by its kind (a TeX macro: #SEL#, #PASTE#, the first #INS#, the bullet of each mark; an AppleScript
// macro: #FILEPATH# and the others). The text keeps them as written; each token is one glyph as wide as its pill, the
// insertion point never stops inside one, deleting next to one deletes all of it, and undo, copy and the text stay as
// they were. No window is shown and the defaults stay in memory.
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSMacroContentTokens.h"
#import "TSPlaceholderToken.h"
#import "TSSyntaxMacroContentScanner.h"
#import "TSAdvancedFindPanelController.h"
#import "TSRegexTextFind.h"
#import "TSRegexFindPattern.h"
#import "TSRegexFindReplacement.h"
#define REQUIRE(...) do { if (!(__VA_ARGS__)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#__VA_ARGS__); exit(1); } } while(0)
// The source's text view and the Advanced Find controllers are not needed here, only their classes.
@implementation TSTextView
@end
@implementation TSAdvancedFindController
@end
@implementation TSAdvancedFindPanelController
@end

static NSArray<NSString *> *Tokens(NSString *text) {
    NSMutableArray *found = [NSMutableArray array];
    [TSSyntaxMacroContentScanner enumerateTokensInString:text usingBlock:^(NSRange range, NSString *symbol) {
        REQUIRE([[text substringWithRange:range] isEqual:symbol]);
        [found addObject:[NSString stringWithFormat:@"%lu:%@", (unsigned long)range.location, symbol]];
    }];
    return found;
}
static TSMacroContentTextView *view; static TSMacroContentLayoutManager *layout;
static void Layout(void) { [layout ensureLayoutForTextContainer:view.textContainer]; }
// The width that the characters of a range take on their line: from their first glyph to the glyph after them (or the
// end of the last one, at the end of the text).
static CGFloat Width(NSRange characters) {
    Layout();
    NSRange glyphs = [layout glyphRangeForCharacterRange:characters actualCharacterRange:NULL];
    CGFloat start = [layout locationForGlyphAtIndex:glyphs.location].x;
    NSUInteger after = NSMaxRange(glyphs);
    if (after < layout.numberOfGlyphs)
        return [layout locationForGlyphAtIndex:after].x - start;
    NSRect last = [layout boundingRectForGlyphRange:NSMakeRange(after - 1, 1) inTextContainer:view.textContainer];
    NSRect line = [layout lineFragmentRectForGlyphAtIndex:after - 1 effectiveRange:NULL];
    return NSMaxX(last) - NSMinX(line) - start;
}
static NSArray<NSValue *> *Ranges(void) { Layout(); return layout.tokenRanges; }
static void Type(NSString *text) { [view insertText:text replacementRange:view.selectedRange]; }

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation();
    [NSApplication sharedApplication];

    // Which occurrences are tokens: the ones the macro replaces.
    REQUIRE([Tokens(@"\\begin{#SEL#}#INS# #INS# #PASTE# •‹note #SEL#› • #FILEPATH#") isEqual:(@[@"7:#SEL#", @"13:#INS#", @"25:#PASTE#", @"33:•", @"40:#SEL#", @"47:•"])]);
    REQUIRE([Tokens(@"--applescript direct\nopen #PDFPATH# -- #SEL# #INS# • #FOLDERPATH##DOCUMENTNAME#") isEqual:(@[@"26:#PDFPATH#", @"53:#FOLDERPATH#", @"65:#DOCUMENTNAME#"])]);
    NSMutableString *every = [NSMutableString stringWithString:@"--applescript\n"];
    for (NSString *symbol in TSSyntaxMacroContentScanner.appleScriptPlaceholders) [every appendFormat:@"%@ ", symbol];
    REQUIRE(Tokens(every).count == 13);
    for (NSString *symbol in TSSyntaxMacroContentScanner.appleScriptPlaceholders) {
        NSString *title = TSPlaceholderTokenTitle(symbol);
        REQUIRE(title.length > 0 && ![title isEqual:TSPlaceholderTokenTitle(@"•")] && ![title isEqual:symbol]);
    }
    REQUIRE([TSPlaceholderTokenTitle(@"#SEL#") isEqual:@"Selected Text"] && [TSPlaceholderTokenTitle(@"#FILEPATH#") isEqual:@"File Path"]);

    // A text view as the macro editor makes it.
    NSTextStorage *storage = [NSTextStorage new];
    layout = [TSMacroContentLayoutManager new];
    [storage addLayoutManager:layout];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(600, CGFLOAT_MAX)];
    [layout addTextContainer:container];
    view = [[TSMacroContentTextView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300) textContainer:container];
    view.richText = NO; view.allowsUndo = YES;
    NSFont *font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    view.font = font;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
    window.releasedWhenClosed = NO; window.contentView = view; [window makeFirstResponder:view];
    REQUIRE(layout.delegate == layout && [layout isKindOfClass:TSAdvancedFindLayoutManager.class]);

    // Each token is one glyph as wide as its pill; its other characters take no room; the text stays as written.
    view.string = @"a#SEL#b#INS#c#INS#z";
    REQUIRE([view.string isEqual:@"a#SEL#b#INS#c#INS#z"]);
    REQUIRE([Ranges() isEqual:(@[[NSValue valueWithRange:NSMakeRange(1, 5)], [NSValue valueWithRange:NSMakeRange(7, 5)]])]);
    CGFloat sel = TSPlaceholderTokenSize(TSPlaceholderTokenTitle(@"#SEL#"), font).width;
    REQUIRE(fabs(Width(NSMakeRange(1, 5)) - sel) < .5 && fabs(Width(NSMakeRange(2, 4))) < .5);
    REQUIRE(fabs(Width(NSMakeRange(7, 5)) - TSPlaceholderTokenSize(TSPlaceholderTokenTitle(@"#INS#"), font).width) < .5);
    CGFloat letter = Width(NSMakeRange(0, 1));
    REQUIRE(fabs(Width(NSMakeRange(13, 5)) - 5 * letter) < .5); // the second #INS# is text
    REQUIRE([[layout titleOfTokenRange:NSMakeRange(1, 5)] isEqual:@"Selected Text"]);
    REQUIRE([layout tokenRangeContainingIndex:3].location == 1 && [layout tokenRangeContainingIndex:6].location == NSNotFound);

    // Drawn as pills in the accent color, with no underline below them.
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSRect pill = [layout boundingRectForGlyphRange:[layout glyphRangeForCharacterRange:NSMakeRange(1, 5) actualCharacterRange:NULL] inTextContainer:container];
    CGFloat scale = rep.pixelsWide / NSWidth(view.bounds);
    NSColor *tint = [[NSColor.controlAccentColor colorWithAlphaComponent:0.16] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSColor *middle = [[rep colorAtX:(NSInteger)(NSMidX(pill) * scale) y:(NSInteger)((NSMinY(pill) + 3) * scale)] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSColor *outside = [[rep colorAtX:(NSInteger)(NSMidX(pill) * scale) y:(NSInteger)((NSMaxY(pill) + 20) * scale)] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    REQUIRE(tint && middle && outside && fabs(middle.redComponent - outside.redComponent) + fabs(middle.blueComponent - outside.blueComponent) + fabs(middle.greenComponent - outside.greenComponent) > 0.03);

    // Typing completes a placeholder: it becomes a token at once. Typing the first line of an AppleScript macro turns
    // the TeX tokens back into text and the AppleScript ones into tokens.
    view.string = @"x"; view.selectedRange = NSMakeRange(1, 0);
    Type(@"#SEL"); REQUIRE(Ranges().count == 0);
    Type(@"#"); REQUIRE([Ranges() isEqual:@[[NSValue valueWithRange:NSMakeRange(1, 5)]]]);
    Type(@"y"); REQUIRE(fabs(Width(NSMakeRange(1, 5)) - sel) < .5 && fabs(Width(NSMakeRange(2, 4))) < .5); // laid out as a token
    [view deleteBackward:nil];
    REQUIRE(NSEqualRanges(view.selectedRange, NSMakeRange(6, 0)));
    Type(@" #FILEPATH#"); REQUIRE(Ranges().count == 1);
    view.selectedRange = NSMakeRange(0, 0); Type(@"--applescript\n");
    REQUIRE([Ranges() isEqual:@[[NSValue valueWithRange:NSMakeRange(21, 10)]]]);
    REQUIRE(fabs(Width(NSMakeRange(15, 5)) - 5 * letter) < .5); // #SEL# is text in an AppleScript macro
    REQUIRE(fabs(Width(NSMakeRange(21, 10)) - TSPlaceholderTokenSize(TSPlaceholderTokenTitle(@"#FILEPATH#"), font).width) < .5);

    // An edit on one line changes the tokens of another: they are laid out again there too.
    view.string = @"--applescrip\nopen #FILEPATH#\n"; Layout();
    REQUIRE(Ranges().count == 0 && fabs(Width(NSMakeRange(18, 10)) - 10 * letter) < .5);
    view.selectedRange = NSMakeRange(12, 0); Type(@"t");
    REQUIRE(Ranges().count == 1 && fabs(Width(NSMakeRange(19, 10)) - TSPlaceholderTokenSize(TSPlaceholderTokenTitle(@"#FILEPATH#"), font).width) < .5);
    view.string = @"#INS#\nx #INS#\n"; Layout();
    REQUIRE([Ranges() isEqual:@[[NSValue valueWithRange:NSMakeRange(0, 5)]]] && fabs(Width(NSMakeRange(8, 5)) - 5 * letter) < .5);
    view.selectedRange = NSMakeRange(5, 0); [view deleteBackward:nil];
    REQUIRE([Ranges() isEqual:@[[NSValue valueWithRange:NSMakeRange(3, 5)]]] && fabs(Width(NSMakeRange(3, 5)) - TSPlaceholderTokenSize(TSPlaceholderTokenTitle(@"#INS#"), font).width) < .5);

    // Moving with the keyboard goes by whole tokens: the insertion point never stops inside one, it goes to the end it
    // moves toward; extending the selection takes in the whole token. A click on a token puts the insertion point after
    // it; a drag takes in every token it touches.
    view.string = @"ab#PASTE#cd";
    view.selectedRange = NSMakeRange(2, 0); [view doCommandBySelector:@selector(moveRight:)];
    REQUIRE(NSEqualRanges(view.selectedRange, NSMakeRange(9, 0)));
    [view doCommandBySelector:@selector(moveLeft:)]; REQUIRE(NSEqualRanges(view.selectedRange, NSMakeRange(2, 0)));
    view.selectedRange = NSMakeRange(1, 0);
    [view doCommandBySelector:@selector(moveRightAndModifySelection:)]; [view doCommandBySelector:@selector(moveRightAndModifySelection:)];
    REQUIRE(NSEqualRanges(view.selectedRange, NSMakeRange(1, 8)));
    REQUIRE(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(5, 0) granularity:NSSelectByCharacter], NSMakeRange(9, 0)));
    REQUIRE(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(2, 0) granularity:NSSelectByCharacter], NSMakeRange(2, 0)));
    REQUIRE(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(1, 3) granularity:NSSelectByCharacter], NSMakeRange(1, 8)));
    REQUIRE(NSEqualRanges([view selectionRangeForProposedRange:NSMakeRange(5, 5) granularity:NSSelectByCharacter], NSMakeRange(2, 8)));

    // Find, replace and undo set exact ranges, which stay: a match may be a part of a token. Searched as the Advanced Find
    // panel does, the last # of #SEL# found backward is the one replaced, and searching forward visits both.
    view.string = @"#SEL#"; view.selectedRange = NSMakeRange(5, 0);
    TSRegexFindPattern *hash = [[TSRegexFindPattern alloc] initWithFindString:@"#" options:0 error:NULL];
    TSRegexTextFind *(^find)(void) = ^{ return [[TSRegexTextFind alloc] initWithString:view.string pattern:hash selectedRanges:view.selectedRanges inSelection:NO error:NULL]; };
    NSArray *matches = [find() matchRangesWithCancellation:nil];
    NSRange hit = [find() nextMatchInRanges:matches forward:NO includingSelection:NO wraps:YES wrapped:NULL];
    view.selectedRange = hit;
    REQUIRE(NSEqualRanges(hit, NSMakeRange(4, 1)) && NSEqualRanges(view.selectedRange, hit));
    TSRegexReplacementTemplate *x = [[TSRegexReplacementTemplate alloc] initWithString:@"X" pattern:hash syntax:TSRegexReplacementSyntaxICU];
    TSRegexFindReplacement *replacement = [find() replacementInSelectionWithTemplate:x];
    REQUIRE(NSEqualRanges(replacement.range, NSMakeRange(4, 1)));
    [view insertText:replacement.string replacementRange:replacement.range];
    REQUIRE([view.string isEqual:@"#SELX"] && Ranges().count == 0);
    view.string = @"#SEL#"; view.selectedRange = NSMakeRange(0, 0);
    matches = [find() matchRangesWithCancellation:nil];
    hit = [find() nextMatchInRanges:matches forward:YES includingSelection:YES wraps:NO wrapped:NULL];
    view.selectedRange = hit; REQUIRE(NSEqualRanges(view.selectedRange, NSMakeRange(0, 1)));
    hit = [find() nextMatchInRanges:matches forward:YES includingSelection:NO wraps:NO wrapped:NULL];
    REQUIRE(NSEqualRanges(hit, NSMakeRange(4, 1)));
    view.selectedRange = hit; REQUIRE(NSEqualRanges(view.selectedRange, NSMakeRange(4, 1)));
    // The editor sets the insertion point inside a token, after Insert of a mark with a note: it stays.
    view.string = @"•‹›"; view.selectedRange = NSMakeRange(2, 0); REQUIRE(NSEqualRanges(view.selectedRange, NSMakeRange(2, 0)));

    // Delete next to a token deletes all of it, as one change that undo brings back.
    view.string = @"ab#PASTE#cd"; [view.undoManager removeAllActions];
    view.selectedRange = NSMakeRange(9, 0); [view deleteBackward:nil];
    REQUIRE([view.string isEqual:@"abcd"] && NSEqualRanges(view.selectedRange, NSMakeRange(2, 0)) && Ranges().count == 0);
    [view.undoManager undo];
    REQUIRE([view.string isEqual:@"ab#PASTE#cd"] && Ranges().count == 1);
    view.selectedRange = NSMakeRange(2, 0); [view deleteForward:nil];
    REQUIRE([view.string isEqual:@"abcd"]);
    view.selectedRange = NSMakeRange(2, 0); [view deleteBackward:nil];
    REQUIRE([view.string isEqual:@"acd"]); // text is deleted a character at a time, as before

    // The text keeps the placeholder as it is written, which copying, saving and Find read.
    view.string = @"x#SEL#y"; view.selectedRange = NSMakeRange(0, 7);
    REQUIRE([[view.string substringWithRange:view.selectedRange] isEqual:@"x#SEL#y"] && view.textStorage.length == 7);
    REQUIRE([view.textStorage attribute:NSAttachmentAttributeName atIndex:1 effectiveRange:NULL] == nil);

    // Marks: the bullet is a token, the note of •‹note› stays text.
    view.string = @"•‹abc›";
    REQUIRE([Ranges() isEqual:@[[NSValue valueWithRange:NSMakeRange(0, 1)]]] && [[layout titleOfTokenRange:NSMakeRange(0, 1)] isEqual:@"Mark"]);
    REQUIRE(fabs(Width(NSMakeRange(0, 1)) - TSPlaceholderTokenSize(@"Mark", font).width) < .5 && Width(NSMakeRange(1, 5)) > 4 * letter);

    [window close];
    puts("PASS: macro placeholders as tokens: which ones, width, drawing, typing, kind, insertion point, delete, undo, copy, marks");
} return 0; }
