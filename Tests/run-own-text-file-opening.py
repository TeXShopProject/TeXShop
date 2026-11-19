#!/usr/bin/env python3
"""Edit Command Completion and Edit Spelling Exclusions open the file itself, for editing.

The production openOwnTextFileAtURL:completionHandler: of TSDocumentController runs in a real
NSDocumentController. When TeXShop's file is a symbolic link, the file it points to is opened (a
link's type is the link's own, and AppKit would not open it). A copy of the file open for preview
only, opened before it became TeXShop's file or through another name, is left as it is (it may
hold annotations) and the file is opened for editing beside it; a copy open for editing is used
again. Documents show no window.
--mutation=link opens the link itself; use-preview uses the copy open for preview only."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
mutation = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--mutation=')), None)
s = (root/'Sources/Document/TSDocumentController.m').read_text(encoding='latin1')
a = s.index('- (void)openOwnTextFileAtURL:'); code = s[a:s.index('\n}\n', a)+3]
def mutate(text, old, new):
    assert text.count(old) == 1, old; return text.replace(old, new)
if mutation == 'link':
    code = mutate(code, 'NSURL *file = url.URLByStandardizingPath.URLByResolvingSymlinksInPath;', 'NSURL *file = url;')
if mutation == 'use-preview':
    code = mutate(code, '\t\tif (! [(TSDocument *)document externalEditor]) {', '\t\tif (YES) {')
program = r'''
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
static NSMutableArray<NSString *> *gReads;
// A document as far as these tests need it; the same file is the same file identifier.
@interface TSDocument : NSDocument
@property BOOL externalEditor;
- (BOOL)isSameFileAs:(NSURL *)url;
@end
@implementation TSDocument
+ (BOOL)autosavesInPlace { return NO; }
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error { [gReads addObject:url.path]; return YES; }
- (void)makeWindowControllers {}
- (BOOL)isSameFileAs:(NSURL *)url {
    id one = nil, other = nil;
    [[NSURL fileURLWithPath:self.fileURL.path] getResourceValue:&one forKey:NSURLFileResourceIdentifierKey error:NULL];
    [[NSURL fileURLWithPath:url.path] getResourceValue:&other forKey:NSURLFileResourceIdentifierKey error:NULL];
    return one && [one isEqual:other];
}
@end
@interface TSDocumentController : NSDocumentController
- (void)openOwnTextFileAtURL:(NSURL *)url completionHandler:(void (^)(NSDocument *document))completionHandler;
@end
@implementation TSDocumentController
- (Class)documentClassForType:(NSString *)type { return [TSDocument class]; }
CODE
@end
static void check(BOOL v, NSString *m) { if (!v) { fprintf(stderr, "FAIL %s\n", m.UTF8String); exit(1); } }
static TSDocument *Open(TSDocumentController *c, NSURL *url) {
    __block TSDocument *opened = nil; __block BOOL done = NO;
    [c openOwnTextFileAtURL:url completionHandler:^(NSDocument *d) { opened = (TSDocument *)d; done = YES; }];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && limit.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    check(done, @"the opening finished");
    return opened;
}
int main(int argc, char **argv) { @autoreleasepool {
    TSInstallAppKitIsolation(); [NSApplication sharedApplication];
    gReads = [NSMutableArray array];
    TSDocumentController *c = [TSDocumentController new];
    check([NSDocumentController sharedDocumentController] == c, @"the probe controller is the shared controller");
    NSString *folder = [@(argv[1]) stringByResolvingSymlinksInPath];
    NSString *real = [folder stringByAppendingPathComponent:@"my-rules.txt"], *linkPath = [folder stringByAppendingPathComponent:@"SpellingExclusions.txt"];
    [@"skip-body proof\n" writeToFile:real atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:linkPath withDestinationPath:real error:NULL];

    // TeXShop's file is a link: the file it points to is opened.
    TSDocument *d = Open(c, [NSURL fileURLWithPath:linkPath]);
    check(d != nil && [gReads.lastObject isEqualToString:real] && [d.fileURL.path isEqualToString:real], @"a link is opened as the file it points to");
    // Opened again, the same document is used.
    NSUInteger reads = gReads.count;
    check(Open(c, [NSURL fileURLWithPath:linkPath]) == d && gReads.count == reads, @"a copy open for editing is used again");
    [d close];

    // A copy open for preview only, under another name (a hard link), is closed and the file is opened again.
    NSString *other = [folder stringByAppendingPathComponent:@"other-name.txt"];
    link(real.fileSystemRepresentation, other.fileSystemRepresentation);
    __block TSDocument *preview = nil; __block BOOL done = NO;
    [c openDocumentWithContentsOfURL:[NSURL fileURLWithPath:other] display:YES completionHandler:^(NSDocument *x, BOOL w, NSError *e) { preview = (TSDocument *)x; done = YES; }];
    while (!done) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    preview.externalEditor = YES;
    reads = gReads.count;
    TSDocument *edit = Open(c, [NSURL fileURLWithPath:linkPath]);
    check(edit != nil && edit != preview && !edit.externalEditor && gReads.count == reads + 1 && [gReads.lastObject isEqualToString:real],
          @"the file is opened for editing beside a copy open for preview only");
    check([c.documents containsObject:preview] && [c.documents containsObject:edit], @"the copy open for preview only is left as it is");
    check(Open(c, [NSURL fileURLWithPath:linkPath]) == edit, @"opened again, the copy for editing is used");
    fprintf(stderr, "PASS: TeXShop's own files open as the file itself, for editing\n");
}}
'''.replace('CODE', code)
with tempfile.TemporaryDirectory(prefix='texshop-own-file-opening-') as folder:
    p = Path(folder); (p/'test.m').write_text(program, encoding='utf-8')
    work = p/'files'; work.mkdir()
    subprocess.run(['xcrun', 'clang', '-I', str(root/'Tests'), '-fobjc-arc', '-Wno-deprecated-declarations', '-framework', 'Cocoa',
                    str(p/'test.m'), '-o', str(p/'test')], check=True)
    subprocess.run([str(p/'test'), str(work)], check=True, timeout=60)
