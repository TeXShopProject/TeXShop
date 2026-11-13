#import "../TestAppKitIsolation.h"
// Show Spelling and Grammar with TeX-aware checking: the panel is shown without
// the system's own search, and the TeX-aware finding stays selected (#38). While
// the panel is shown, the command hides it and searches nothing. Uses a
// stand-in spell checker and panel; nothing is ordered on screen.
#import <Cocoa/Cocoa.h>
#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"
#import "SessionChecker.h"

static NSMutableArray<NSString *> *sSteps;
@implementation SessionChecker
+ (instancetype)sharedSpellChecker { static SessionChecker *checker; if (!checker) checker = [self new]; return checker; }
- (BOOL)hasLearnedWord:(NSString *)word { abort(); }
- (void)unlearnWord:(NSString *)word { abort(); }
- (NSString *)language { return @"en"; }
- (NSArray *)availableLanguages { return @[@"en"]; }
- (NSArray *)guessesForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag { return nil; }
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word { [sSteps addObject:[@"panel word " stringByAppendingString:word]]; }
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)start language:(NSString *)language
                          wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count
{
    [sSteps addObject:@"search"];
    return [s rangeOfString:@"zzqq[ab]" options:NSRegularExpressionSearch range:NSMakeRange((NSUInteger)start, s.length - (NSUInteger)start)];
}
@end
@interface StandInPanel : NSPanel
@property BOOL shown;
@end
@implementation StandInPanel
- (BOOL)isVisible { return self.shown; }
- (void)orderFront:(id)sender { [sSteps addObject:@"show"]; self.shown = YES; }
@end
@interface OpenPanelTextView : NSTextView @end
@implementation OpenPanelTextView
- (void)showFindIndicatorForRange:(NSRange)range {}
@end

static int sFailures;
#define CHECK(cond, what) do { if (!(cond)) { sFailures++; fprintf(stderr, "FAIL: %s (%s)\n", what, [[sSteps description] UTF8String]); } } while (0)

int main(void)
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        StandInPanel *panel = [[StandInPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
            styleMask:NSWindowStyleMaskUtilityWindow backing:NSBackingStoreBuffered defer:YES];
        SessionChecker.sharedSpellChecker.spellingPanel = panel;
        NSTextView *view = [[OpenPanelTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        view.string = @"\\zzqqa{x} words zzqqb more words";
        TSSpellExclusions *rules = [TSSpellExclusions sharedExclusions];
        __block NSUInteger hidden = 0;
        void (^hide)(void) = ^{ [sSteps addObject:@"system"]; hidden++; panel.shown = NO; };

        // The panel is not shown: it is shown and the TeX-aware search is run.
        sSteps = [NSMutableArray array];
        view.selectedRange = NSMakeRange(0, 0);
        [TSSpellSupport showSpellingPanelForTextView:view mask:[rules maskForText:view.string] hidePanel:hide];
        CHECK(hidden == 0 && ![sSteps containsObject:@"system"], "opening does not run the system's showGuessPanel:");
        CHECK([sSteps.firstObject isEqualToString:@"show"], "the panel is shown before the search");
        CHECK(panel.shown, "the panel is shown");
        CHECK([[view.string substringWithRange:view.selectedRange] isEqualToString:@"zzqqb"],
              "the TeX-aware finding (not the command name) is selected");
        CHECK([sSteps.lastObject isEqualToString:@"panel word zzqqb"], "the panel shows the TeX-aware finding");

        // The panel is shown: the command hides it and searches nothing.
        sSteps = [NSMutableArray array];
        NSRange before = view.selectedRange;
        [TSSpellSupport showSpellingPanelForTextView:view mask:[rules maskForText:view.string] hidePanel:hide];
        CHECK([sSteps isEqual:@[@"system"]] && hidden == 1, "a shown panel is hidden, with no search");
        CHECK(NSEqualRanges(view.selectedRange, before), "hiding the panel keeps the selection");
        CHECK(!panel.shown, "the panel is hidden");

        if (sFailures) return 1;
        puts("PASS: Show Spelling and Grammar opens the panel without the system's search, and hides a shown panel");
    }
    return 0;
}
