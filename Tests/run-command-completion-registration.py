#!/usr/bin/env python3
"""While a command completion file is open for editing, nothing else writes to it.

Edit Command Completion opens the file and turns off registering selections as completions.
The production reReadCommandCompletionData and commandCompletionFileIsOpen of TSAppDelegate run
here with a real NSDocumentController: rereading the list after the open file is saved keeps
registering off; once the file is closed, rereading turns it on again. The library repair and the
encodings are stand-ins. --mutation=always-on turns registering on after every reading."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/App/TSAppDelegate.m').read_text(encoding='utf-8')
def method(signature):
    a = s.index(signature); return s[a:s.index('\n}\n', a)+3]
methods = method('- (void)reReadCommandCompletionData //') + method('- (BOOL)commandCompletionFileIsOpen')
if mutation == 'always-on':
    old = '    g_canRegisterCommandCompletion = ! [self commandCompletionFileIsOpen];\n'
    assert methods.count(old) == 1; methods = methods.replace(old, '    g_canRegisterCommandCompletion = YES;\n')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
NSMutableString *g_commandCompletionList; BOOL g_canRegisterCommandCompletion;
@interface GlobalData : NSObject
@property (copy) NSString *CommandCompletionPath;
@end
@implementation GlobalData
+ (instancetype)sharedGlobalData { static id shared; if (!shared) shared = [self new]; return shared; }
@end
static NSString *TSLibraryBundledPath(NSString *name) { return nil; }
static id TSLibraryReadableCheck(void) { return nil; }
static BOOL TSLibraryRestoreMissingFile(NSString *path, NSString *bundled, id check) { return [[NSFileManager defaultManager] fileExistsAtPath:path]; }
@interface TSEncodingSupport : NSObject
@end
@implementation TSEncodingSupport
+ (instancetype)sharedInstance { static id shared; if (!shared) shared = [self new]; return shared; }
- (NSStringEncoding)defaultEncoding { return NSISOLatin1StringEncoding; }
@end
// A document as far as these tests need it: whether it is a command completion file is
// decided by TSDocument from the file itself (run-texshop-own-files.py).
@interface TSDocument : NSDocument
@property BOOL isCommandCompletionFile;
@end
@implementation TSDocument
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error { return YES; }
@end
@interface Probe : NSObject
- (BOOL)commandCompletionFileIsOpen;
@end
@implementation Probe
METHODS
@end
static void check(BOOL v, const char *m) { if (!v) { fprintf(stderr, "FAIL %s\n", m); exit(1); } }
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    NSString *path = [@(argv[1]) stringByAppendingPathComponent:@"CommandCompletion.txt"];
    [@"\\section\nfirst\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [GlobalData sharedGlobalData].CommandCompletionPath = path;
    Probe *app = [Probe new];
    [app reReadCommandCompletionData];
    check(g_canRegisterCommandCompletion && [g_commandCompletionList containsString:@"first"], "the list is read and selections can be registered");
    // The file is open for editing (Edit Command Completion turns registering off) and is saved: the list is read again.
    TSDocument *open = [TSDocument new]; open.fileURL = [NSURL fileURLWithPath:path]; open.isCommandCompletionFile = YES;
    TSDocument *other = [TSDocument new]; other.fileURL = [NSURL fileURLWithPath:[path stringByAppendingString:@".tex"]];
    [[NSDocumentController sharedDocumentController] addDocument:other];
    [[NSDocumentController sharedDocumentController] addDocument:open];
    g_canRegisterCommandCompletion = NO;
    [@"\\section\nfirst\nsecond\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [app reReadCommandCompletionData];
    check([g_commandCompletionList containsString:@"second"], "the saved list is read again");
    check(!g_canRegisterCommandCompletion, "while the file is open, nothing else writes to it");
    // Closed, it may be written to again.
    [[NSDocumentController sharedDocumentController] removeDocument:open];
    [app reReadCommandCompletionData];
    check(g_canRegisterCommandCompletion, "once the file is closed, selections can be registered again");
    // Opened under another name (a hard link), it is still the command completion file.
    TSDocument *alias = [TSDocument new]; alias.fileURL = [NSURL fileURLWithPath:[path stringByAppendingString:@".link"]]; alias.isCommandCompletionFile = YES;
    [[NSDocumentController sharedDocumentController] addDocument:alias];
    check([app commandCompletionFileIsOpen], "a command completion file open under another name counts");
    [[NSDocumentController sharedDocumentController] removeDocument:alias];
    check(![app commandCompletionFileIsOpen], "closed under another name, it no longer counts");
    fprintf(stderr, "PASS: the command completion file open for editing is not written to by registering\n");
}}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='texshop-completion-registration-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='utf-8')
    work = p/'files'; work.mkdir()
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-fobjc-arc', '-Wno-unused-function', '-framework', 'Cocoa',
                    str(p/'test.m'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test'), str(work)], check=True, timeout=60)
