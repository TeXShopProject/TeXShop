#!/usr/bin/env python3
"""The encoding chosen in the save panel is the one the file is saved in.

The production save panel methods of TSDocument run in a real NSDocument. A
stand-in takes the place of the save panel, so nothing appears on screen. The
test chooses Shift JIS in the encoding menu, saves, and checks the bytes of
the file. A source with an encoding magic comment opens the menu at that
encoding and cannot be changed. --mutation=unwired removes the menu's action;
--mutation=no-magic starts the menu at the document encoding instead;
--mutation=unlocked leaves the menu enabled under a magic comment."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/TSDocument.m').read_text(encoding='latin1')
def method(signature):
    a = s.index(signature); return s[a:s.index('\n}\n', a)+3]
methods = '\n'.join(method(x) for x in [
    '- (void)runModalSavePanelForSaveOperation:', '- (void)saveToURL:(NSURL *)absoluteURL ofType: (NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation delegate:',
    '- (BOOL)prepareSavePanel:', '- (void) chooseTempEncoding: sender',
    '- (void)setUpEncodingMenuInSavePanel:', '- (NSString *)encodingNameInMagicComment'])
if mutation == 'unwired':
    old = '        openSaveBox.action = @selector(chooseTempEncoding:);\n'
    assert old in methods; methods = methods.replace(old, '')
if mutation == 'no-magic':
    old = '\t\t_tempencoding = [[TSEncodingSupport sharedInstance] stringEncodingForKey: name];\n'
    assert old in methods; methods = methods.replace(old, '\t\t;\n')
if mutation == 'unlocked':
    old = '\tmenu.enabled = ! fixed;\n'
    assert old in methods; methods = methods.replace(old, '')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import <objc/runtime.h>
#define XMLINDEX 42
#define EncodingMenuInSaveDialogKey @"EncodingMenuInSaveDialog"
#define UseOldHeadingCommandsKey @"UseOldHeadingCommands"
static BOOL atLeastHighSierra = YES;
// In-memory stand-in for the user defaults: nothing is written to disk.
@interface FakeDefaults : NSObject
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation FakeDefaults
- (BOOL)boolForKey:(NSString *)key { return [key isEqualToString:EncodingMenuInSaveDialogKey]; }
@end
static FakeDefaults *gDefaults;
#define SUD gDefaults
@interface TSEncodingSupport : NSObject
+ (instancetype)sharedInstance;
- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)aTarget action:(SEL)anAction;
- (BOOL)knowsEncodingKey:(NSString *)key;
- (NSStringEncoding)stringEncodingForKey:(NSString *)key;
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
// Same construction as the production menu, with a few encodings.
- (void)addEncodingsToMenu:(NSMenu *)menu withTarget:(id)aTarget action:(SEL)anAction {
    NSStringEncoding encs[] = {NSUTF8StringEncoding, NSShiftJISStringEncoding, NSISOLatin1StringEncoding};
    for (int i = 0; i < 3; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString localizedNameOfStringEncoding:encs[i]] action:anAction keyEquivalent:@""];
        if (aTarget) [item setTarget:aTarget];
        [item setTag:encs[i]];
        [menu addItem:item];
    }
}
- (BOOL)knowsEncodingKey:(NSString *)key { return [key isEqualToString:@"SJIS"]; }
// The production method shows an alert for an unknown name, so the panel must not ask for one.
- (NSStringEncoding)stringEncodingForKey:(NSString *)key {
    if (![key isEqualToString:@"SJIS"]) { fprintf(stderr, "FAIL an unknown encoding name is looked up\n"); exit(1); }
    return NSShiftJISStringEncoding;
}
@end
// The real super method would show a save panel; the test plays the panel's part instead.
@interface PanelFreeDocument : NSDocument
@end
@implementation PanelFreeDocument
- (void)runModalSavePanelForSaveOperation:(NSSaveOperationType)o delegate:(id)d didSaveSelector:(SEL)s contextInfo:(void *)c { }
@end
@interface TSDocument : PanelFreeDocument {
    @public
    NSPopUpButton *openSaveBox, *openSaveBoxHS, *saveFormatMenu;
    NSView *openSaveView, *openSaveViewHS;
    NSSavePanel *theSavePanel;
    NSStringEncoding _encoding, _tempencoding, _unreadableEncoding;
    NSString *fileExtensions[1];
    NSTextStorage *_textStorage;
}
@property BOOL fileIsXML;
@end
@implementation TSDocument
+ (BOOL)autosavesInPlace { return YES; }
+ (NSArray *)writableTypes { return @[@"public.plain-text"]; }
+ (NSArray *)readableTypes { return @[@"public.plain-text"]; }
- (NSString *)fileNameExtensionForType:(NSString *)t saveOperation:(NSSaveOperationType)o { return @"tex"; }
- (NSArray *)writableTypesForSaveOperation:(NSSaveOperationType)o { return @[@"public.plain-text"]; }
- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    return [@"\u65e5\u672c\u8a9e abc" dataUsingEncoding:_encoding allowLossyConversion:YES];
}
METHODS
@end
@interface PanelStandIn : NSObject
@property (strong) NSView *accessoryView;
@end
@implementation PanelStandIn
@end
static void check(BOOL v, NSString *m) { if (!v) { fprintf(stderr, "FAIL %s\n", m.UTF8String); exit(1); } }
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    // Never show a real open or save panel.
    for (Class c in @[[NSSavePanel class], [NSOpenPanel class]]) {
        Method m = class_getClassMethod(c, @selector(savePanel));
        if (m) method_setImplementation(m, imp_implementationWithBlock(^id(id s) { check(NO, @"No real save panel is opened"); return nil; }));
    }
    method_setImplementation(class_getInstanceMethod([NSSavePanel class], @selector(init)),
        imp_implementationWithBlock(^id(id s) { check(NO, @"No real save panel is opened"); return nil; }));
    gDefaults = [FakeDefaults new];
    NSURL *folder = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
    TSDocument *doc = [TSDocument new];
    doc.fileType = @"public.plain-text";
    doc->_encoding = NSUTF8StringEncoding;
    doc->_textStorage = [[NSTextStorage alloc] initWithString:@"\\documentclass{article}\n"];
    // The accessory view that holds the encoding menu, as in TSDocument.nib.
    doc->openSaveView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
    doc->openSaveBox = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(100, 8, 200, 26) pullsDown:NO];
    [doc->openSaveView addSubview:doc->openSaveBox];
    // A stand-in for the save panel: no panel is shown and no panel service is used.
    PanelStandIn *panel = [PanelStandIn new];
    panel.accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 30)];
    [panel.accessoryView addSubview:[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 200, 26) pullsDown:NO]];
    [doc runModalSavePanelForSaveOperation:NSSaveAsOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
    check([doc prepareSavePanel:(NSSavePanel *)panel], @"The save panel is prepared");
    NSPopUpButton *box = doc->openSaveBox;
    check(panel.accessoryView == doc->openSaveView && box.numberOfItems == 3, @"The save panel shows the encoding menu");
    check(box.selectedTag == NSUTF8StringEncoding, @"The menu starts at the document encoding");
    check(box.enabled, @"Without a magic comment the encoding can be chosen");
    // Choose Shift JIS as the user would, through the menu item itself.
    [box.menu performActionForItemAtIndex:[box indexOfItemWithTag:NSShiftJISStringEncoding]];
    check(box.selectedTag == NSShiftJISStringEncoding, @"Shift JIS is selected");
    // Then the panel's Save button saves to the chosen place.
    NSURL *target = [folder URLByAppendingPathComponent:@"chosen.tex"];
    __block BOOL done = NO;
    [doc saveToURL:target ofType:@"public.plain-text" forSaveOperation:NSSaveAsOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        done = [[NSFileManager defaultManager] fileExistsAtPath:target.path];
    }
    check(done, @"The document was saved");
    NSData *bytes = [NSData dataWithContentsOfURL:target];
    NSData *sjis = [@"\u65e5\u672c\u8a9e abc" dataUsingEncoding:NSShiftJISStringEncoding];
    check(doc->_encoding == NSShiftJISStringEncoding, @"The chosen encoding becomes the document encoding");
    check([bytes isEqualToData:sjis], @"The file is written in the chosen encoding");
    fprintf(stderr, "PASS: the encoding chosen in the save panel is used for the saved file\n");
    // A magic comment names the encoding the file is saved in, so the menu starts there.
    NSArray *sources = @[@"% !TEX TS-program = uplatex\n% !TEX encoding = SJIS\n\\documentclass{jsarticle}\n",
                         @"%!TEX encoding = SJIS  \n", @"% !TEX encoding = Bogus\n", @"% !TEX encoding =\n"];
    NSStringEncoding expected[] = {NSShiftJISStringEncoding, NSShiftJISStringEncoding, NSUTF8StringEncoding, NSUTF8StringEncoding};
    for (NSUInteger i = 0; i < sources.count; i++) {
        TSDocument *magic = [TSDocument new];
        magic->_encoding = NSUTF8StringEncoding;
        magic->_textStorage = [[NSTextStorage alloc] initWithString:sources[i]];
        magic->openSaveView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 40)];
        magic->openSaveBox = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(100, 8, 200, 26) pullsDown:NO];
        [magic->openSaveView addSubview:magic->openSaveBox];
        PanelStandIn *p2 = [PanelStandIn new];
        p2.accessoryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 30)];
        [magic runModalSavePanelForSaveOperation:NSSaveAsOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
        check([magic prepareSavePanel:(NSSavePanel *)p2], @"The save panel is prepared");
        check(magic->openSaveBox.selectedTag == expected[i], [NSString stringWithFormat:@"The menu starts at the magic comment encoding (case %lu)", (unsigned long)i]);
        check(magic->_tempencoding == expected[i], @"The encoding to save in follows the menu");
        check(magic->openSaveBox.enabled == (i >= 2), [NSString stringWithFormat:@"The menu is fixed only under a known magic comment (case %lu)", (unsigned long)i]);
    }
    // The menu belongs to the document and is reused by its next Save As.
    doc->openSaveBox.enabled = NO;
    doc->_textStorage = [[NSTextStorage alloc] initWithString:@"no magic comment\n"];
    [doc runModalSavePanelForSaveOperation:NSSaveAsOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
    check([doc prepareSavePanel:(NSSavePanel *)panel], @"The save panel is prepared again");
    check(doc->openSaveBox.enabled, @"A menu fixed before can be chosen again without a magic comment");
    fprintf(stderr, "PASS: the save panel menu shows and fixes the encoding named by a magic comment\n");
}}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-save-encoding-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='latin1')
    out = p/'out'; out.mkdir()
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-fobjc-arc', '-Wno-deprecated-declarations', '-framework', 'Cocoa',
                    str(p/'test.m'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test'), str(out)], check=True, timeout=30)
