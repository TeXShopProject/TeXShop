#!/usr/bin/env python3
"""Notices about an opened file go to the window that shows its source on screen.

The production notice methods of TSDocument and makeKeyAndOrderFront: of TSTextEditorWindow run
with stand-in windows and alerts, so no sheet appears on screen. With separate windows the
source window gets the notice. In the combined window the source window stays hidden, so the
notice waits until the combined window is on screen and goes there. A line ending notice
waits while the encoding notice is shown. --mutation=hidden-window sends notices to the
source window even when it is hidden; --mutation=no-wait drops them when no window is ready."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/TSDocument.m').read_text(encoding='latin1')
a = s.index('- (void)tryLineEndingNotice:'); b = s.index('\n}\n', s.index('- (void)tryBadEncodingDialog:', a)) + 3
notices = s[a:b]
if mutation == 'hidden-window':
    old = '\treturn (window.isVisible && ! window.attachedSheet) ? window : nil;\n'
    assert old in notices; notices = notices.replace(old, '\treturn textWindow;\n')
if mutation == 'no-wait':
    old = '\t\tif ((shown.isVisible && shown.attachedSheet) || _openingNoticeAttempts++ < 20)\n\t\t\t[self tryOpeningNoticesLater];\n'
    assert old in notices; notices = notices.replace(old, '')
for real, stand_in in [('NSWindow', 'WindowStandIn'), ('NSAlert', 'AlertStandIn'), ('NSModalResponse', 'NSInteger'), ('NSControlStateValueOn', '1')]:
    notices = notices.replace(real, stand_in)
w = (root/'Sources/TSTextEditorWindow.m').read_text(encoding='latin1')
a = w.index('- (void)makeKeyAndOrderFront:'); b = w.index('\n}\n', a) + 3
window = w[a:b]
program = r'''
#import <Foundation/Foundation.h>
#include <sys/xattr.h>
static const char *TSLineEndingNoticeAttribute = "org.texshop.line-ending-notice-off";
@interface WindowStandIn : NSObject
@property BOOL isVisible;
@property id attachedSheet;
@property NSString *name;
- (void)makeKeyAndOrderFront:(id)sender;
@end
@implementation WindowStandIn
- (void)makeKeyAndOrderFront:(id)sender { self.isVisible = YES; }
@end
static NSMutableArray *gSheets;   // "window:kind" for each sheet asked for
@interface ButtonStandIn : NSObject
@property NSString *title;
@property NSInteger state;
@end
@implementation ButtonStandIn
@end
@interface AlertStandIn : NSObject
@property NSString *messageText, *informativeText;
@property BOOL showsSuppressionButton;
@property ButtonStandIn *suppressionButton;
@end
@implementation AlertStandIn
- (instancetype)init { if ((self = [super init])) _suppressionButton = [ButtonStandIn new]; return self; }
- (void)beginSheetModalForWindow:(WindowStandIn *)window completionHandler:(void (^)(NSInteger))handler {
    [gSheets addObject:[window.name stringByAppendingString:@":line-endings"]]; window.attachedSheet = self;
}
@end
static void NSBeginAlertSheet(NSString *title, id d, id a, id o, WindowStandIn *window, id dl, SEL s1, SEL s2, void *c, NSString *msg, ...) {
    [gSheets addObject:[window.name stringByAppendingString:@":encoding"]]; window.attachedSheet = @"sheet";
}
@interface TSEncodingSupport : NSObject
+ (instancetype)sharedInstance;
- (NSString *)localizedNameForStringEncoding:(NSStringEncoding)e;
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
- (NSString *)localizedNameForStringEncoding:(NSStringEncoding)e { return @"UTF-8"; }
@end
#define isTeX 0
#define isOther 1
@interface TSDocument : NSObject {
@public
    BOOL useFullSplitWindow, showBadEncodingDialog;
    WindowStandIn *textWindow, *fullSplitWindow;
    NSInteger _lineEndingNotice, _openingNoticeAttempts;
    NSStringEncoding _badEncoding;
}
@property NSURL *fileURL;
- (void)tryBadEncodingDialog:(WindowStandIn *)window;
@end
@implementation TSDocument
- (BOOL)externalEditor { return NO; }
- (BOOL)useFullSplitWindow { return useFullSplitWindow; }
- (NSInteger)documentType { return isTeX; }
NOTICES
@end
@interface TSTextEditorWindow : WindowStandIn
@property TSDocument *myDocument;
@end
@implementation TSTextEditorWindow
WINDOW
@end
static void check(BOOL v, NSString *m) { if (!v) { fprintf(stderr, "FAIL %s (sheets: %s)\n", m.UTF8String, [gSheets componentsJoinedByString:@" "].UTF8String); exit(1); } }
static void runFor(double seconds) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static TSDocument *document(BOOL combined, NSInteger lineEndings, BOOL badEncoding) {
    TSDocument *d = [TSDocument new];
    TSTextEditorWindow *text = [TSTextEditorWindow new]; text.name = @"source"; text.myDocument = d;
    d->textWindow = text;
    d->fullSplitWindow = [WindowStandIn new]; d->fullSplitWindow.name = @"combined";
    d->useFullSplitWindow = combined; d->_lineEndingNotice = lineEndings; d->showBadEncodingDialog = badEncoding;
    return d;
}
int main(void) { @autoreleasepool {
    gSheets = [NSMutableArray array];
    // Separate windows: the source window shows the notice.
    TSDocument *d = document(NO, 1, NO);
    [d->textWindow makeKeyAndOrderFront:nil];
    check([gSheets isEqual:@[@"source:line-endings"]] && d->_lineEndingNotice == 0, @"the source window shows the notice");
    // Combined window: the source window stays hidden and the notice waits for the combined window.
    [gSheets removeAllObjects];
    d = document(YES, 3, NO);
    [d->textWindow makeKeyAndOrderFront:nil];
    check(!d->textWindow.isVisible && gSheets.count == 0 && d->_lineEndingNotice == 3, @"no notice goes to the hidden source window");
    runFor(0.7);
    check(gSheets.count == 0 && d->_lineEndingNotice == 3, @"the notice waits while the combined window is not on screen");
    d->fullSplitWindow.isVisible = YES;
    runFor(0.7);
    check([gSheets isEqual:@[@"combined:line-endings"]] && d->_lineEndingNotice == 0, @"the combined window shows the notice once it is on screen");
    // An encoding notice first; the line ending notice waits until its sheet is closed.
    [gSheets removeAllObjects];
    d = document(NO, 1, YES);
    [d->textWindow makeKeyAndOrderFront:nil];
    check([gSheets isEqual:@[@"source:encoding"]] && d->_lineEndingNotice == 1, @"the encoding notice comes first");
    runFor(1.2);
    check(gSheets.count == 1, @"the line ending notice waits while the encoding sheet is shown");
    d->textWindow.attachedSheet = nil;
    runFor(0.7);
    check([gSheets isEqual:@[@"source:encoding", @"source:line-endings"]] && d->_lineEndingNotice == 0, @"the line ending notice follows the encoding notice");
    fprintf(stderr, "PASS: notices about an opened file go to the window on screen, one after another\n");
}}
'''.replace('NOTICES', notices).replace('WINDOW', window)
with tempfile.TemporaryDirectory(prefix='texshop-opening-notices-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', '-framework', 'Foundation', str(p/'test.m'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test')], check=True, timeout=60)
