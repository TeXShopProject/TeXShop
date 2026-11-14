#import "TestAppKitIsolation.h"
// Open the compiled document nib of one language the way a document window does, with
// production code: TSTextView's layout manager replacement, and TSDocument's
// setTextView:, applyInvisibleCharactersShowing and showHideInvisibleCharacters:.
// Nothing is shown on screen and no user settings are read.
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import <objc/runtime.h>
#import "TSLayoutManager.h"
#import "MarkerKeys.h"
#define SUD [NSUserDefaults standardUserDefaults]
NSColor *InvisibleColor;
static int failures;
static void Require(NSString *what, BOOL ok) { if (!ok) { printf("FAIL %s\n", what.UTF8String); failures++; } }

@interface TSTextView : NSTextView
@end
@implementation TSTextView
- (void)awakeFromNib
{
    [super awakeFromNib];
    //@@TSTextView layout manager@@
}
@end

@interface TSDocument : NSObject {
@public
    NSTextView *textView, *textView1, *textView2, *stringWindowTextView;
    BOOL invisibleCharactersShowing;
}
@property NSInteger colorized;
@end
@implementation TSDocument
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {}
- (void)applyExperimentInvisibleCharacters {}
- (void)colorizeAll { self.colorized++; }
//@@TSDocument methods@@
@end

static BOOL Showing(NSTextView *view)
{
    TSLayoutManager *layout = (TSLayoutManager *)view.layoutManager;
    return [layout isKindOfClass:TSLayoutManager.class] && [[layout valueForKey:@"invisibleCharactersShowing"] boolValue];
}

int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    InvisibleColor = NSColor.systemRedColor;
    NSString *path = @(argv[1]);
    NSNib *nib = [[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil];
    TSDocument *document = [TSDocument new];
    NSArray *objects = nil;
    Require(@"document nib loads", [nib instantiateWithOwner:document topLevelObjects:&objects]);

    NSTextView *source = document->textView, *upper = document->textView1, *lower = document->textView2;
    // What the nib connects: the source editor and both parts of a split source are TSTextViews.
    Require(@"textView is the source editor textView1", source == upper);
    Require(@"textView1 is a TSTextView", [upper isKindOfClass:TSTextView.class]);
    Require(@"textView2 is another TSTextView", [lower isKindOfClass:TSTextView.class] && lower != upper);
    Require(@"the text annotation panel has its own text view", document->stringWindowTextView && ![document->stringWindowTextView isKindOfClass:TSTextView.class]
            && [document->stringWindowTextView.window.identifier isEqual:@"TextPanel"]);
    Require(@"each source editor draws with a TSLayoutManager", [source.layoutManager isKindOfClass:TSLayoutManager.class]
            && [lower.layoutManager isKindOfClass:TSLayoutManager.class] && upper.layoutManager != lower.layoutManager);

    // windowControllerDidLoadNib: applies the setting while textView is still the nib's.
    document->invisibleCharactersShowing = YES;
    @try {
        [document applyInvisibleCharactersShowing];
        Require(@"invisible characters shown in the source", Showing(upper) && Showing(lower));
        // The menu command, then a split source with the lower part active, then back.
        [document showHideInvisibleCharacters:nil];
        Require(@"Hide Invisible Characters reaches both parts", !Showing(upper) && !Showing(lower) && document.colorized == 1);
        [document setTextView:lower];
        Require(@"the lower part becomes the active editor", document->textView == lower);
        [document showHideInvisibleCharacters:nil];
        Require(@"Show Invisible Characters from the lower part reaches both parts", Showing(upper) && Showing(lower));
        [document setTextView:upper];
        [document showHideInvisibleCharacters:nil];
        Require(@"Hide Invisible Characters from the upper part reaches both parts", !Showing(upper) && !Showing(lower));
    } @catch (NSException *exception) {
        Require([NSString stringWithFormat:@"no exception while applying invisible characters: %@", exception.reason], NO);
    }

    // A text view with a plain NSLayoutManager is skipped rather than stopping the window.
    NSTextView *plain = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    document->textView = plain;
    document->invisibleCharactersShowing = YES;
    @try {
        [document applyInvisibleCharactersShowing];
        Require(@"the editors still follow the setting", Showing(upper) && Showing(lower));
    } @catch (NSException *exception) {
        Require([NSString stringWithFormat:@"a plain NSLayoutManager is skipped: %@", exception.reason], NO);
    }
    for (id object in objects) if ([object isKindOfClass:NSWindow.class]) [object orderOut:nil];
    if (!failures) printf("PASS %s\n", path.UTF8String);
    return failures ? 1 : 0;
}}
