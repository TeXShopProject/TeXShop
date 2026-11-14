#import "../TestAppKitIsolation.h"
// Find Next in a long document shows the misspelled word in the middle of the
// view, also after the text around it has been laid out to be drawn (#38).
// Uses a stand-in spell checker; the window is never ordered on screen.
#import <Cocoa/Cocoa.h>
#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"
#import "SessionChecker.h"

@implementation SessionChecker
+ (instancetype)sharedSpellChecker { static SessionChecker *checker; if (!checker) checker = [self new]; return checker; }
- (BOOL)hasLearnedWord:(NSString *)word { abort(); }
- (void)unlearnWord:(NSString *)word { abort(); }
- (NSString *)language { return @"en"; }
- (NSArray *)availableLanguages { return @[@"en"]; }
- (NSArray *)guessesForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag { return nil; }
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word {}
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)start language:(NSString *)language
                          wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count
{
    return [s rangeOfString:@"zzqqa" options:0 range:NSMakeRange((NSUInteger)start, s.length - (NSUInteger)start)];
}
@end
@interface CenterTextView : NSTextView @end
@implementation CenterTextView
- (void)showFindIndicatorForRange:(NSRange)range {}
@end

static int sFailures;
#define CHECK(cond, ...) do { if (!(cond)) { sFailures++; fprintf(stderr, "FAIL: "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } } while (0)

// A line of plain prose at about `fraction` of the text, where the word is inserted.
static NSUInteger ProseLine(NSString *text, double fraction)
{
    NSRange line = [text lineRangeForRange:NSMakeRange((NSUInteger)(text.length * fraction), 0)];
    while (NSMaxRange(line) < text.length) {
        NSString *s = [text substringWithRange:line];
        if (s.length > 40 && [NSCharacterSet.letterCharacterSet characterIsMember:[s characterAtIndex:0]] &&
            [s rangeOfString:@"\\"].location == NSNotFound && [s rangeOfString:@"%"].location == NSNotFound) return line.location;
        line = [text lineRangeForRange:NSMakeRange(NSMaxRange(line), 0)];
    }
    abort();
}

static void Run(NSString *source, double fraction, BOOL contiguous, CGFloat width, CGFloat height)
{
    NSUInteger at = ProseLine(source, fraction);
    NSMutableString *text = [source mutableCopy];
    [text insertString:@"zzqqa " atIndex:at];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    scroll.hasVerticalScroller = YES;
    NSSize size = scroll.contentSize;
    NSTextView *view = [[CenterTextView alloc] initWithFrame:NSMakeRect(0, 0, size.width, size.height)];
    view.minSize = NSMakeSize(0, size.height);
    view.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    view.verticallyResizable = YES;
    view.horizontallyResizable = NO;
    view.autoresizingMask = NSViewWidthSizable;
    view.textContainer.containerSize = NSMakeSize(size.width, CGFLOAT_MAX);
    view.textContainer.widthTracksTextView = YES;
    view.layoutManager.allowsNonContiguousLayout = !contiguous;   // as TSTextView does
    view.font = [NSFont userFixedPitchFontOfSize:12];
    view.continuousSpellCheckingEnabled = NO;
    scroll.documentView = view;
    window.contentView = scroll;
    view.string = text;
    [window displayIfNeeded];                                     // the top of the text is shown
    view.selectedRange = NSMakeRange(0, 0);

    NSString *word = [TSSpellSupport findNextMisspellingInTextView:view
        mask:[[TSSpellExclusions sharedExclusions] maskForText:view.string]];
    NSRange bad = NSMakeRange(at, 5);
    CHECK([word isEqualToString:@"zzqqa"] && NSEqualRanges(view.selectedRange, bad),
          "%.2f: the word is found and selected", fraction);
    NSLayoutManager *lm = view.layoutManager;
    if (!contiguous)
        CHECK(lm.firstUnlaidCharacterIndex < at, "%.2f %gx%g: the text before the word is not laid out in full",
              fraction, width, height);

    // Draw, as the window does, and lay out what is shown again: the word must not move.
    for (int k = 0; k < 2; k++) {
        [window displayIfNeeded];
        [lm ensureLayoutForBoundingRect:view.visibleRect inTextContainer:view.textContainer];
    }
    NSRect r = [lm boundingRectForGlyphRange:[lm glyphRangeForCharacterRange:bad actualCharacterRange:NULL]
                             inTextContainer:view.textContainer];
    r = NSOffsetRect(r, view.textContainerOrigin.x, view.textContainerOrigin.y);
    NSRect visible = view.visibleRect;
    CGFloat offset = NSMidY(r) - NSMidY(visible);
    CHECK(NSMinY(r) >= NSMinY(visible) && NSMaxY(r) <= NSMaxY(visible),
          "%s %.2f %gx%g: the word is visible (word %.0f..%.0f, view %.0f..%.0f)",
          contiguous ? "contiguous" : "non-contiguous", fraction, width, height,
          NSMinY(r), NSMaxY(r), NSMinY(visible), NSMaxY(visible));
    CHECK(fabs(offset) <= height * 0.05,
          "%s %.2f %gx%g: the word is in the middle of the view (%.0f from the middle)",
          contiguous ? "contiguous" : "non-contiguous", fraction, width, height, offset);
    [window close];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *source = [NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL];
        if (source.length < 100000) { fprintf(stderr, "FAIL: a long document is needed\n"); return 1; }
        NSUInteger runs = 0;
        for (int contiguous = 0; contiguous < 2; contiguous++)
            for (NSNumber *width in @[@450, @700])
                for (NSNumber *height in @[@400, @800, @1200])
                    for (NSNumber *fraction in @[@0.05, @0.15, @0.35, @0.6, @0.9]) {
                        @autoreleasepool { Run(source, fraction.doubleValue, contiguous, width.doubleValue, height.doubleValue); }
                        runs++;
                    }
        if (sFailures) { fprintf(stderr, "%d of the checks in %lu runs failed\n", sFailures, (unsigned long)runs); return 1; }
        printf("spell centring: %lu runs passed\n", (unsigned long)runs);
    }
    return 0;
}
