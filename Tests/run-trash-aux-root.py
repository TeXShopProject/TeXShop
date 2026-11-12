#!/usr/bin/env python3
"""Trash Aux Files from a chapter file trashes the root's files, Option or not."""
from pathlib import Path
import re, subprocess, sys, tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Document/TSDocument.m').read_text(encoding='latin-1')
rootfile = (root / 'Sources/Document/TSDocument-RootFile.m').read_text(encoding='latin-1')

def method(text, signature):
    start = text.index(signature)
    end = text.index('\n}\n', start) + 3
    return text[start:end]

methods = method(source, '- (void)trashAUXFiles: sender') + method(source, '- (void)trashAUXWithAggressiveness:(BOOL)aggressive')
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'setting-only-root':
    methods = methods.replace('\ttheSource = [[self textView] string];\n\tif ([self checkMasterFile',
                              '\ttheSource = [[self textView] string];\n\tif (! [SUD boolForKey:AggressiveTrashAUXKey]) { [self trashAUX]; return; }\n\tif ([self checkMasterFile')
elif mutation == 'stale-flag':
    methods = methods.replace('\taggressiveTrash = aggressive;\n', '')
elif mutation == 'plain-forward':
    rootfile = rootfile.replace('[obj trashAUXWithAggressiveness:aggressiveTrash];', '[obj trashAUX];', 1)

# Every branch of the root lookup that hands the task to the root document forwards the flag.
forwards = rootfile.count('[obj trashAUXWithAggressiveness:aggressiveTrash];')
plain = rootfile.count('[obj trashAUX];')

methods = methods.replace('GetCurrentKeyModifiers()', 'gModifiers')
program = r'''
#import <Cocoa/Cocoa.h>
enum { optionKey = 0x0800, shiftKey = 0x0200 };
enum { RootForTrashAUX = 6 };
static NSUInteger gModifiers;
static BOOL gAggressiveSetting;
#define SUD Defaults()
#define AggressiveTrashAUXKey @"AggressiveTrashAUX"
@interface FakeDefaults : NSObject
- (BOOL)boolForKey:(NSString *)key;
@end
@implementation FakeDefaults
- (BOOL)boolForKey:(NSString *)key { return [key isEqualToString:AggressiveTrashAUXKey] && gAggressiveSetting; }
@end
static FakeDefaults *Defaults(void) { static FakeDefaults *d; if (!d) d = [FakeDefaults new]; return d; }
@interface Doc : NSObject {
@public
    BOOL aggressiveTrash, fileIsTex;
}
@property (copy) NSString *name;
@property (strong) Doc *rootDocument;
@property (strong) NSURL *url;
@property (copy) NSString *text;
@property (strong) NSMutableArray *log;
- (NSURL *)fileURL;
- (NSTextView *)textView;
- (void)trashAUX;
- (void)trashAUXWithAggressiveness:(BOOL)aggressive;
@end
@implementation Doc
- (NSURL *)fileURL { return self.url; }
- (NSTextView *)textView { NSTextView *v = [NSTextView new]; v.string = self.text ?: @""; return v; }
- (BOOL)checkMasterFile:(NSString *)source forTask:(int)task { return NO; }
- (BOOL)checkRootFile_forTask:(int)task
{
    if (!self.rootDocument || task != RootForTrashAUX) return NO;
    Doc *obj = self.rootDocument;
    if (FORWARDS) [obj trashAUXWithAggressiveness:aggressiveTrash]; else [obj trashAUX];
    return YES;
}
- (void)trashAUX { [self.log addObject:[NSString stringWithFormat:@"%@:%@", self.name, aggressiveTrash ? @"tree" : @"folder"]]; }
METHODS
@end
static int failures;
static void Expect(NSString *label, NSArray *log, NSArray *want)
{
    if (![log isEqualToArray:want]) { failures++; printf("FAIL %s: %s\n", label.UTF8String, [log description].UTF8String); }
}
int main(void) { @autoreleasepool {
    NSMutableArray *log = [NSMutableArray array];
    Doc *rootDoc = [Doc new]; rootDoc.name = @"root"; rootDoc.log = log; rootDoc->fileIsTex = YES; rootDoc.url = [NSURL fileURLWithPath:@"/tmp/book/book.tex"];
    Doc *chapter = [Doc new]; chapter.name = @"chapter"; chapter.log = log; chapter->fileIsTex = YES; chapter.url = [NSURL fileURLWithPath:@"/tmp/book/ch/ch1.tex"];
    chapter.rootDocument = rootDoc;
    Doc *single = [Doc new]; single.name = @"single"; single.log = log; single->fileIsTex = YES; single.url = [NSURL fileURLWithPath:@"/tmp/single.tex"];
    Doc *untitled = [Doc new]; untitled.name = @"untitled"; untitled.log = log; untitled->fileIsTex = YES;
    Doc *other = [Doc new]; other.name = @"other"; other.log = log; other->fileIsTex = NO; other.url = [NSURL fileURLWithPath:@"/tmp/x.txt"];

    struct { NSUInteger modifiers; BOOL setting; NSString *want; } cases[] = {
        {0, NO, @"folder"}, {optionKey, NO, @"tree"}, {0, YES, @"tree"}, {optionKey | shiftKey, NO, @"tree"}};
    for (int i = 0; i < 4; i++) {
        gModifiers = cases[i].modifiers; gAggressiveSetting = cases[i].setting;
        rootDoc->aggressiveTrash = !([cases[i].want isEqualToString:@"tree"]);
        [log removeAllObjects]; [chapter trashAUXFiles:nil];
        Expect([NSString stringWithFormat:@"chapter case %d goes to the root", i], log, @[[@"root:" stringByAppendingString:cases[i].want]]);
        [log removeAllObjects]; [single trashAUXFiles:nil];
        Expect([NSString stringWithFormat:@"single file case %d", i], log, @[[@"single:" stringByAppendingString:cases[i].want]]);
        [log removeAllObjects]; [untitled trashAUXFiles:nil];
        Expect(@"untitled document trashes nothing", log, @[]);
        [log removeAllObjects]; [other trashAUXFiles:nil];
        Expect(@"non-TeX document trashes nothing", log, @[]);
    }
    return failures ? 1 : 0;
} }
'''.replace('METHODS', methods).replace('FORWARDS', '1' if (forwards == 3 and plain == 0) else '0')

with tempfile.TemporaryDirectory(prefix='texshop-trash-aux-root-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(program)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', str(src), '-o', str(exe)], check=True)
    r = subprocess.run([str(exe)], capture_output=True, text=True)
    if mutation:
        if r.returncode == 0: raise SystemExit('FAIL: mutation %s was not detected' % mutation)
        print('detected mutation', mutation)
    else:
        if r.returncode: raise SystemExit(r.stdout + r.stderr)
        print('PASS: chapter files go to the root with and without Option or AggressiveTrashAUX; the Option tree sweep reaches the root; single, untitled and non-TeX documents')
