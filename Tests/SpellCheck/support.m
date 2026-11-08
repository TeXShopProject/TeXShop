#import "../TestAppKitIsolation.h"
// Learned-word lookup and Find Next, with a stand-in spell checker that never
// learns, ignores or forgets words.
#import <Cocoa/Cocoa.h>
#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"
#import "SessionChecker.h"

static NSMutableArray<NSString *> *sAsked;
static NSUInteger sOffMain, sChecks;
static NSMutableArray<NSString *> *sChecked;
@implementation SessionChecker
+ (instancetype)sharedSpellChecker { static SessionChecker *checker; if (!checker) checker = [self new]; return checker; }
- (BOOL)hasLearnedWord:(NSString *)word
{
    if (![NSThread isMainThread]) sOffMain++;
    [sAsked addObject:word];
    return [word isEqualToString:@"zzlearned"] || [word isEqualToString:@"München"];
}
- (void)unlearnWord:(NSString *)word { abort(); }
- (NSString *)language { return @"en"; }
- (NSArray *)availableLanguages { return @[@"en", @"de"]; }
- (NSArray *)guessesForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag { self.guessedWord=[string substringWithRange:range]; return self.guesses; }
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word {}
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)start language:(NSString *)language
                          wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count
{
    sChecks++;
    [sChecked addObject:[NSString stringWithFormat:@"%@:%@", language ?: @"-",
        [[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""]]];
    return [s rangeOfString:@"zzbad" options:0 range:NSMakeRange((NSUInteger)start, s.length - (NSUInteger)start)];
}
@end
@interface SupportTextView : NSTextView @end
@implementation SupportTextView
- (void)showFindIndicatorForRange:(NSRange)range {}
@end

static void Spin(double seconds)
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
}

static NSArray<NSString *> *Find(NSString *text, BOOL masked, double *callSeconds, NSUInteger *turns)
{
    __block NSArray<NSString *> *found = nil;
    __block NSUInteger between = 0;
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    [TSSpellSupport findLearnedWordsInText:text masked:masked completion:^(NSArray<NSString *> *words) { found = words; }];
    *callSeconds = CFAbsoluteTimeGetCurrent() - start;
    // Count main-queue turns that run while the lookup is going on.
    __block void (^tick)(void) = ^{ if (!found) { between++; dispatch_async(dispatch_get_main_queue(), tick); } };
    dispatch_async(dispatch_get_main_queue(), tick);
    for (int k = 0; k < 2000 && !found; k++) Spin(.01);
    tick = nil;
    *turns = between;
    return found;
}

int main(void)
{
    @autoreleasepool {
        TSInstallAppKitIsolation(); [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        sAsked = [NSMutableArray array];
        sChecked = [NSMutableArray array];
        int failures = 0;

        NSMutableString *text = [NSMutableString stringWithString:
            @"\\includegraphics{zzfigure} Hello zzlearned \\label{zzlabel} M\\\"unchen $zzmath$\n"];
        for (NSUInteger k = 0; k < 20000; k++) [text appendFormat:@"w%lux ", (unsigned long)k];
        double seconds; NSUInteger turns;
        NSArray<NSString *> *found = Find(text, YES, &seconds, &turns);
        NSSet<NSString *> *asked = [NSSet setWithArray:sAsked];
        printf("masked text: learned=%s, %lu words looked up, call returned after %.1f ms, %lu main-queue turns during the lookup, %lu lookups off the main thread\n",
               [[found componentsJoinedByString:@","] UTF8String], (unsigned long)sAsked.count, seconds * 1000, (unsigned long)turns, (unsigned long)sOffMain);
        if (![found isEqualToArray:@[@"München", @"zzlearned"]]) { puts("FAIL: learned words"); failures++; }
        for (NSString *markup in @[@"includegraphics", @"zzfigure", @"label", @"zzlabel", @"zzmath", @"unchen"])
            if ([asked containsObject:markup]) { printf("FAIL: markup word '%s' looked up\n", markup.UTF8String); failures++; }
        if (sOffMain) { puts("FAIL: spell checker used off the main thread"); failures++; }
        if (seconds > 0.05 || turns < 10) { puts("FAIL: lookup blocks the main thread"); failures++; }

        [sAsked removeAllObjects];
        found = Find(text, NO, &seconds, &turns);
        asked = [NSSet setWithArray:sAsked];
        printf("plain text: %lu words looked up, includegraphics looked up=%d\n", (unsigned long)sAsked.count, [asked containsObject:@"includegraphics"]);
        if (![asked containsObject:@"includegraphics"] || ![found containsObject:@"zzlearned"]) { puts("FAIL: plain text words"); failures++; }

        // Find Next: neighbouring segments in the same language go to the checker
        // together; segments without words are not checked on their own.
        NSTextView *view = [[SupportTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
        view.string = @"one \\foreignlanguage{english}{two} three \\foreignlanguage{german}{vier} "
                      @"\\foreignlanguage{german}{ } \\foreignlanguage{german}{fuenf} six zzbad";
        TSSpellMask *mask = [[TSSpellExclusions sharedExclusions] maskForText:view.string];
        NSString *word = [TSSpellSupport findNextMisspellingInTextView:view mask:mask];
        printf("Find Next: %lu segments, %lu checker calls (%s), found %s\n", (unsigned long)mask.languageSegments.count,
               (unsigned long)sChecks, [[sChecked componentsJoinedByString:@" | "] UTF8String], word.UTF8String);
        NSArray *expected = @[@"-:one{two}three{", @"de:vier}{}{fuenf", @"-:}sixzzbad"];
        if (![word isEqualToString:@"zzbad"] || ![sChecked isEqualToArray:expected]) { puts("FAIL: Find Next runs"); failures++; }

        // Editing the exclusion rules is offered only while TeX-aware spell checking is on.
        // The setting is given in the argument domain, which is not saved.
        NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(editSpellingExclusions:) keyEquivalent:@""];
        NSMenuItem *forget = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(forgetLearnedWords:) keyEquivalent:@""];
        for (NSNumber *on in @[@NO, @YES]) {
            [[NSUserDefaults standardUserDefaults] setVolatileDomain:@{@"TeXAwareSpellChecking": on} forName:NSArgumentDomain];
            if ([TSSpellSupport validateMenuItem:edit] != on.boolValue || ![TSSpellSupport validateMenuItem:forget]) {
                printf("FAIL: Edit Spelling Exclusions menu item with TeX-aware spell checking %s\n", on.boolValue ? "on" : "off");
                failures++;
            }
        }

        if (failures) return 1;
        puts("PASS: learned words looked up among the checked words without blocking; Find Next checks one run per language.");
    }
    return 0;
}
