// added by Terada: never learns, ignores or removes dictionary entries.
#import <Cocoa/Cocoa.h>
#import "TSSpellSupport.h"
#import "TSSpellExclusions.h"
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
    NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,500,300)];
    window.contentView = view; view.string = text; view.allowsUndo = YES;
    [window orderBack:nil]; [window makeMainWindow]; [window makeFirstResponder:view];
    return view;
}
static NSTextField *Replacement(void) {
    for (NSView *view in NSSpellChecker.sharedSpellChecker.accessoryView.subviews)
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
    Review(a); [a.textStorage replaceCharactersInRange:NSMakeRange(0,1) withString:@"x"];
    [TSSpellSupport changeAll:nil]; NSCAssert([a.string isEqual:@"xzqqa zzqqa"], @"edit must invalidate replacement");
    a.string=@"zzqqa zzqqa"; Review(a); [TSSpellSupport changeAll:nil];
    NSCAssert([a.string isEqual:@"fixed fixed"], @"current review must replace both words");
    [a.undoManager undo]; NSCAssert([a.string isEqual:@"zzqqa zzqqa"], @"single undo must restore original");
    a.selectedRange=NSMakeRange(1,0);
    NSDate *until=[NSDate dateWithTimeIntervalSinceNow:.8];
    while(until.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    NSCAssert(NSEqualRanges(a.selectedRange,NSMakeRange(1,0)), @"no stale delayed selection");
    puts("PASS: switched/edited documents protected; current Change All and Undo work");
}return 0;}
