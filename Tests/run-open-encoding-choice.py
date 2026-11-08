#!/usr/bin/env python3
"""An encoding chosen in the Open panel applies to that opening only.

The production runModalOpenPanel:forTypes:, openDocumentWithContentsOfURL:display:
completionHandler: and takeEncoding:chosenForURL: of TSDocumentController run in a real
NSDocumentController. A stand-in replaces the panel and its encoding menu, so nothing appears
on screen; opening, reusing an open document and failing are AppKit's own. A file opened with
a chosen encoding is read in it once. A chosen file that is already open, or that fails to
open, keeps no choice for a later reading, whether it is opened with the completion handler
(as the Open panel does) or with the older synchronous method (as SyncTeX and root files do).
--mutation=kept removes the clean-up; --mutation=kept-sync removes it for open documents;
--mutation=kept-failed removes it for documents that cannot be made."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/TSDocumentController.m').read_text(encoding='latin1')
a = s.index('- (NSInteger)runModalOpenPanel:'); b = s.index('- (void)noteNewRecentDocument:', a)
code = s[a:b]
if mutation == 'kept':
    for old in ('\t\tif (key)\n\t\t\t[self->_chosenEncodingURLs removeObject: key];\n', '\tif (document && key)\n\t\t[_chosenEncodingURLs removeObject: key];\n'):
        assert old in code; code = code.replace(old, '')
if mutation == 'kept-failed':
    old = '\tif (! document && key)\n\t\t[_chosenEncodingURLs removeObject: key];\n'
    assert old in code; code = code.replace(old, '')
if mutation == 'kept-sync':
    old = '\tif (document && key)\n\t\t[_chosenEncodingURLs removeObject: key];\n'
    assert old in code; code = code.replace(old, '')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <objc/runtime.h>
// Stand-ins for the encoding menu of the Open panel and for the panel itself.
@interface MenuStandIn : NSObject
@property NSInteger chosenTag;
@end
@implementation MenuStandIn
- (void)removeAllItems {}
- (id)menu { return self; }
- (void)selectItemWithTag:(NSInteger)tag {}
- (id)selectedCell { return self; }
- (NSInteger)tag { return _chosenTag; }
@end
@interface PanelStandIn : NSObject
@property NSArray *URLs;
@end
@implementation PanelStandIn
- (void)setAccessoryView:(id)view {}
@end
@interface TSEncodingSupport : NSObject
+ (instancetype)sharedInstance;
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
- (NSStringEncoding)defaultEncoding { return NSUTF8StringEncoding; }
- (void)addEncodingsToMenu:(id)menu withTarget:(id)t action:(SEL)a {}
@end
// The panel answers OK at once; it is never shown.
@interface PanelFreeController : NSDocumentController
@end
@implementation PanelFreeController
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)panel forTypes:(NSArray *)types { return NSModalResponseOK; }
- (BOOL)presentError:(NSError *)error { return NO; }
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)w delegate:(id)d didPresentSelector:(SEL)s contextInfo:(void *)c {}
- (id)makeDocumentWithContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    // A file named missing-... cannot be opened at all.
    if ([url.lastPathComponent hasPrefix:@"missing"]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
        return nil;
    }
    return [super makeDocumentWithContentsOfURL:url ofType:type error:error];
}
@end
@interface TSDocumentController : PanelFreeController {
@public NSStringEncoding _encoding, _chosenEncoding; NSMutableSet *_chosenEncodingURLs; id encodingView; MenuStandIn *encodingMenu;
}
- (BOOL)takeEncoding:(NSStringEncoding *)encoding chosenForURL:(NSURL *)url;
@end
static NSMutableDictionary *gRead;   // path -> encoding the document was read in
@interface ProbeDocument : NSDocument
@end
@implementation ProbeDocument
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error {
    NSStringEncoding e = 0;
    BOOL chosen = [(TSDocumentController *)[NSDocumentController sharedDocumentController] takeEncoding:&e chosenForURL:url];
    gRead[url.path] = @(chosen ? e : 0);
    if ([url.lastPathComponent hasPrefix:@"broken"]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
        return NO;
    }
    return YES;
}
- (void)makeWindowControllers {}
@end
@implementation TSDocumentController
CODE
- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)error { return @"public.plain-text"; }
- (Class)documentClassForType:(NSString *)type { return [ProbeDocument class]; }
@end
static void check(BOOL v, NSString *m) { if (!v) { fprintf(stderr, "FAIL %s\n", m.UTF8String); exit(1); } }
static void openAll(TSDocumentController *c, NSArray *urls) {
    __block NSInteger pending = urls.count;
    for (NSURL *url in urls)
        [c openDocumentWithContentsOfURL:url display:NO completionHandler:^(NSDocument *d, BOOL wasOpen, NSError *e) { pending--; }];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (pending > 0 && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    check(pending == 0, @"every opening finished");
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    gRead = [NSMutableDictionary dictionary];
    TSDocumentController *c = [TSDocumentController new];
    check([NSDocumentController sharedDocumentController] == c, @"the probe controller is the shared controller");
    c->encodingMenu = [MenuStandIn new];
    c->encodingMenu.chosenTag = NSISOLatin1StringEncoding;
    NSString *folder = @(argv[1]);
    NSURL *(^file)(NSString *) = ^NSURL *(NSString *name) {
        NSString *path = [folder stringByAppendingPathComponent:name];
        if (![name hasPrefix:@"missing"]) [@"Caf\u00e9\n" writeToFile:path atomically:YES encoding:NSISOLatin1StringEncoding error:NULL];
        return [NSURL fileURLWithPath:path];
    };
    NSURL *open = file(@"open.tex"), *fresh = file(@"fresh.tex"), *broken = file(@"broken.tex"), *missing = file(@"missing.tex");
    // open.tex is already open in UTF-8.
    openAll(c, @[open]);
    check([gRead[open.path] integerValue] == 0, @"a file opened without a choice gets none");
    // The user chooses Latin 1 for all four files in the Open panel.
    PanelStandIn *panel = [PanelStandIn new];
    panel.URLs = @[open, fresh, broken, missing];
    [c runModalOpenPanel:(NSOpenPanel *)panel forTypes:nil];
    [gRead removeAllObjects];
    openAll(c, @[open, fresh, broken, missing]);
    check(gRead[open.path] == nil, @"the open document is reused, not read");
    check([gRead[fresh.path] unsignedIntegerValue] == NSISOLatin1StringEncoding, @"a new file is read in the chosen encoding");
    check([gRead[broken.path] unsignedIntegerValue] == NSISOLatin1StringEncoding, @"a file that fails to read was read in the chosen encoding");
    // Later readings, such as reloads after external changes, find no choice.
    for (NSURL *url in @[open, fresh, broken, missing]) {
        NSStringEncoding e = 0;
        check(![c takeEncoding:&e chosenForURL:url], [NSString stringWithFormat:@"no choice is left for %@", url.lastPathComponent]);
    }
    // The same for a file chosen while it is open and then opened with the synchronous method.
    [c runModalOpenPanel:(NSOpenPanel *)panel forTypes:nil];
    NSError *error = nil;
    check([c openDocumentWithContentsOfURL:open display:NO error:&error] != nil, @"the open document is found");
    NSStringEncoding e = 0;
    check(![c takeEncoding:&e chosenForURL:open], @"no choice is left after the synchronous method reuses the document");
    // And for a file that cannot be made into a document, opened with the synchronous method.
    [c runModalOpenPanel:(NSOpenPanel *)panel forTypes:nil];
    check([c openDocumentWithContentsOfURL:missing display:NO error:&error] == nil, @"the missing file does not open");
    check(![c takeEncoding:&e chosenForURL:missing], @"no choice is left after the synchronous method fails to make the document");
    fprintf(stderr, "PASS: an encoding chosen in the Open panel is used once and not left for reused or failed openings\n");
}}
'''.replace('CODE', code)
with tempfile.TemporaryDirectory(prefix='texshop-open-choice-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    out = p/'files'; out.mkdir()
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-fobjc-arc', '-Wno-deprecated-declarations', '-framework', 'Cocoa', str(p/'test.m'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test'), str(out)], check=True, timeout=60)
