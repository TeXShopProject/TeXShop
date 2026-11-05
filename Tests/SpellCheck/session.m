// Never learns, ignores or removes dictionary entries.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"
// An inert public-API checker prevents panel-frame and personal-dictionary writes.
#import "SessionChecker.h"
@implementation SessionChecker
+ (instancetype)sharedSpellChecker { static SessionChecker *checker; if(!checker) checker=[self new]; return checker; }
- (BOOL)hasLearnedWord:(NSString *)word { abort(); }
- (void)unlearnWord:(NSString *)word { abort(); }
- (NSString *)language { return @"en"; }
- (NSArray *)availableLanguages { return @[@"en"]; }
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word {}
- (NSRange)checkSpellingOfString:(NSString *)s startingAt:(NSInteger)start language:(NSString *)language
                          wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count {
    return [s rangeOfString:@"zzqqa" options:0 range:NSMakeRange(start,s.length-start)];
}
@end
@interface SessionTextView : NSTextView @end
@implementation SessionTextView
- (void)showFindIndicatorForRange:(NSRange)range {}
@end
@interface SessionApplication : NSApplication
@property NSWindow *reviewWindow;
@end
@implementation SessionApplication
- (NSWindow *)mainWindow { return self.reviewWindow; }
@end
@interface SessionWindow : NSWindow @end
@implementation SessionWindow
- (BOOL)canBecomeMainWindow { return YES; }
@end
static NSTextView *View(NSString *text) {
    SessionWindow *window = [[SessionWindow alloc] initWithContentRect:NSMakeRect(-20000,-20000,500,300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    NSTextView *view = [[SessionTextView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    window.contentView = view; view.string = text; view.allowsUndo = YES;
    view.continuousSpellCheckingEnabled=NO;view.grammarCheckingEnabled=NO;view.automaticSpellingCorrectionEnabled=NO;
    [window makeMainWindow]; [window makeFirstResponder:view];
    return view;
}
static NSTextField *Replacement(void) {
    for (NSView *view in SessionChecker.sharedSpellChecker.accessoryView.subviews)
        if ([view isKindOfClass:NSTextField.class]) return (NSTextField *)view;
    abort();
}
static void Review(NSTextView *v) {
    [(SessionApplication *)NSApp setReviewWindow:v.window]; [v.window makeMainWindow]; [v.window makeFirstResponder:v]; v.selectedRange=NSMakeRange(0,0);
    NSString *word=[TSSpellSupport findNextMisspellingInTextView:v mask:[[TSSpellExclusions sharedExclusions] maskForText:v.string]];
    NSCAssert(word.length, @"fixture must contain a misspelling");
    Replacement().stringValue=@"fixed";
}
int main(void) {@autoreleasepool {
    [SessionApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSTextView *a=View(@"zzqqa zzqqa"), *b=View(@"zzqqb zzqqb");
    Review(a); [(SessionApplication *)NSApp setReviewWindow:b.window]; [b.window makeMainWindow]; [b.window makeFirstResponder:b];
    [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"zzqqa zzqqa"] && [b.string isEqual:@"zzqqb zzqqb"], @"switch must invalidate replacement");
    Review(a); [a.textStorage replaceCharactersInRange:NSMakeRange(6,1) withString:@"x"];
    [TSSpellSupport changeAll:nil]; NSCAssert([a.string isEqual:@"zzqqa xzqqa"], @"edit must invalidate replacement");
    a.string=@"zzqqa zzqqa"; Review(a); a.selectedRange=NSMakeRange(6,5);
    [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"zzqqa zzqqa"], @"selection-only change must invalidate replacement");
    Review(a); NSTextView *split=[[SessionTextView alloc] initWithFrame:NSMakeRect(0,0,10,10)];
    [a.window.contentView addSubview:split]; [a.window makeFirstResponder:split];
    [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"zzqqa zzqqa"], @"first-responder-only change must invalidate replacement");
    [split removeFromSuperview];
    a.string=@"zzqqa zzqqa"; Review(a); [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"fixed fixed"], @"current review must replace both words");
    [a.undoManager undo]; NSCAssert([a.string isEqual:@"zzqqa zzqqa"], @"single undo must restore original");
    a.selectedRange=NSMakeRange(1,0);
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:.8];
    while(until.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    NSCAssert(NSEqualRanges(a.selectedRange,NSMakeRange(1,0)), @"no stale delayed selection");
    puts("PASS: switched/edited documents protected; current Change All and Undo work");
}return 0;}
