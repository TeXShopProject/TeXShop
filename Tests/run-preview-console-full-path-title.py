#!/usr/bin/env python3
"""Check that the titles of the Preview window and the console follow Show Full Path at once.

Every way of naming the Preview window (opening, typesetting, reading a PDF changed outside
TeXShop) and the console goes through one place, which keeps the path shown. Turning Show Full
Path renames the Preview window and the console at once,
and a later update of the PDF does not bring the file name back. The test compiles the methods of
TSDocument that name these windows into a small stand-in, with windows kept off screen and
settings kept in memory."""
from pathlib import Path
import argparse
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
DOCUMENT = 'Sources/Document/TSDocument.m'
JOBS = 'Sources/Typesetting/TSDocument-Jobs.m'
PREVIEW = 'Sources/Windows/TSPreviewWindow.m'
TITLES = 'Sources/Windows/TSWindowTitles.h'

MUTATIONS = {
    # The Preview window always shows the file name.
    'preview-file-name-only': (TITLES, 'return showFullPath ? path : path.lastPathComponent;', 'return path.lastPathComponent;'),
    # The console always shows the file name.
    'console-file-name-only': (TITLES, 'NSString *name = showFullPath ? path : path.lastPathComponent;', 'NSString *name = path.lastPathComponent;'),
    # Reading a PDF changed outside TeXShop names the window by the file name again.
    'external-update-file-name': (DOCUMENT, '    [self showPreviewTitleForPath:path];\n', '    [self.pdfKitWindow setTitle:path.lastPathComponent];\n'),
    # The console is named by the file name after typesetting.
    'typeset-console-file-name': (JOBS, '\t\t[self showConsoleTitleForPath: imagePath];\n',
                                  '\t\t[outputWindow setTitle: [[[imagePath lastPathComponent] stringByDeletingPathExtension] stringByAppendingString:@" console"]];\n'),
    # Turning the switch leaves the console as it was.
    'switch-leaves-console': (DOCUMENT, '\t[self refreshPreviewTitle];\n\t[self refreshConsoleTitle];\n', '\t[self refreshPreviewTitle];\n'),
    # The Preview window names itself from the source file when it comes to the front.
    'preview-names-itself': (PREVIEW, '\t[self.myDocument refreshPreviewTitle];\n',
                             '\tif([self.myDocument fileURL] != nil ) [self setTitle:[[[self.myDocument fileTitleName] stringByDeletingPathExtension] stringByAppendingString: @".pdf"]];\n'),
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

sources = {name: (root / name).read_text() for name in (DOCUMENT, JOBS, PREVIEW, TITLES)}
if args.mutation:
    name, old, new = MUTATIONS[args.mutation]
    assert sources[name].count(old) == 1, args.mutation
    sources[name] = sources[name].replace(old, new)

checks = 0
def check(ok, message):
    global checks
    checks += 1
    if not ok:
        print('FAIL:', message, file=sys.stderr)
        sys.exit(1)

def method(text, signature):
    start = text.index(signature)
    return text[start:text.index('\n}\n', start) + 3]

# Source checks: nothing but the two refresh methods names the Preview window or the console.
document = sources[DOCUMENT]
rest = document
for signature in ('- (void) refreshPreviewTitle', '- (void) refreshConsoleTitle'):
    rest = rest.replace(method(document, signature), '')
found = []
for path in sorted((root / 'Sources').rglob('*.m')):
    rel = str(path.relative_to(root))
    text = rest if rel == DOCUMENT else sources.get(rel, path.read_text())
    found += [f'{rel}: {line.strip()}' for line in text.splitlines()
              if re.search(r'(pdfKitWindow|outputWindow)\s+setTitle', line) and not line.strip().startswith('//')]
check(not found, f'a window is named outside the document: {found[:1]}')
preview = sources[PREVIEW]
body = method(preview, '- (void) becomeMainWindow')
check('[self.myDocument refreshPreviewTitle]' in body and 'setTitle' not in body,
      'the Preview window asks its document for the title when it comes to the front')
jobs = sources[JOBS]
check(jobs.count('[self showPreviewTitleForPath: imagePath];') == 2 and '[self showConsoleTitleForPath: imagePath];' in jobs,
      'typesetting names the Preview window and the console through the document')
check(document.count('[self showPreviewTitleForPath:') + document.count('[self showPreviewTitleForPath: ') >= 6,
      'opening and updating name the Preview window through the document')

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSWindowTitles.h"
static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
@interface TestDefaults : NSObject
@property (strong) NSMutableDictionary *values;
@end
@implementation TestDefaults
+ (instancetype)shared { static TestDefaults *d; if (!d) { d = [TestDefaults new]; d.values = [NSMutableDictionary dictionary]; } return d; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { self.values[key] = @(value); }
@end
#define SUD [TestDefaults shared]
static NSString *ShowFullPathEnabledKey = @"ShowFullPathEnabled";
@interface TSDocument : NSDocument {
@public
    BOOL showFullPath;
    NSWindow *outputWindow;
}
@property (strong) NSWindow *pdfKitWindow;
@property (strong) NSWindowController *standardController;
@property (copy) NSString *previewTitlePath;
@property (copy) NSString *consoleTitlePath;
- (void) showPreviewTitleForPath: (NSString *)path;
- (void) showConsoleTitleForPath: (NSString *)path;
- (void) refreshPreviewTitle;
- (void) refreshConsoleTitle;
- (void) changeShowFullPath: sender;
@end
@implementation TSDocument
- (void) fixShowFullPathButton {}
METHODS
@end
static NSWindow *offscreen(void) {
    // Never ordered front: the window stays off screen.
    return [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
}
int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *source = @"/Users/someone/a folder/sample.tex";
        NSString *pdf = @"/Users/someone/a folder/sample.pdf";
        TSDocument *document = [[TSDocument alloc] init];
        document.fileURL = [NSURL fileURLWithPath:source];
        document.pdfKitWindow = offscreen();
        document->outputWindow = offscreen();

        // Before a PDF is shown, the Preview window is named after the source file.
        document->showFullPath = YES;
        [document refreshPreviewTitle];
        check([document.pdfKitWindow.title isEqualToString:pdf], @"no PDF yet: the PDF path of the source file");

        // Switch off: file names.
        document->showFullPath = NO;
        [document showPreviewTitleForPath:pdf];
        [document showConsoleTitleForPath:pdf];
        check([document.pdfKitWindow.title isEqualToString:@"sample.pdf"], @"switch off: the Preview window shows the file name");
        check([document->outputWindow.title isEqualToString:@"sample console"], @"switch off: the console shows the file name");

        // Turning the switch on renames both at once.
        [document changeShowFullPath:nil];
        check(document->showFullPath, @"the switch is on");
        check([[TestDefaults shared].values[ShowFullPathEnabledKey] boolValue], @"the setting is saved");
        check([document.pdfKitWindow.title isEqualToString:pdf], @"switch on: the Preview window shows the full path at once");
        check([document->outputWindow.title isEqualToString:@"/Users/someone/a folder/sample console"], @"switch on: the console shows the full path at once");

        // A PDF changed outside TeXShop, or a new typesetting: still the full path.
        [document showPreviewTitleForPath:pdf];
        [document showConsoleTitleForPath:pdf];
        check([document.pdfKitWindow.title isEqualToString:pdf], @"after an update: the Preview window keeps the full path");
        check([document->outputWindow.title isEqualToString:@"/Users/someone/a folder/sample console"], @"after typesetting: the console keeps the full path");

        // The window coming to the front keeps the path of the PDF it shows.
        NSString *other = @"/Users/someone/out/other name.pdf";
        [document showPreviewTitleForPath:other];
        [document refreshPreviewTitle];
        check([document.pdfKitWindow.title isEqualToString:other], @"the title is the path of the PDF shown");

        // Turning the switch off renames both at once.
        [document changeShowFullPath:nil];
        check([document.pdfKitWindow.title isEqualToString:@"other name.pdf"], @"switch off: the Preview window shows the file name at once");
        check([document->outputWindow.title isEqualToString:@"sample console"], @"switch off: the console shows the file name at once");

        // A console never used for typesetting keeps the title it has.
        TSDocument *fresh = [[TSDocument alloc] init];
        fresh->outputWindow = offscreen();
        fresh->outputWindow.title = @"Console";
        fresh->showFullPath = YES;
        [fresh refreshConsoleTitle];
        [fresh refreshPreviewTitle];
        check([fresh->outputWindow.title isEqualToString:@"Console"], @"untitled: the console keeps its title");
        printf("%lu\n", (unsigned long)checks);
    }
    return 0;
}
'''

methods = ''.join(method(document, signature) for signature in (
    '- (void) changeShowFullPath: sender', '- (void) showPreviewTitleForPath:', '- (void) refreshPreviewTitle',
    '- (void) showConsoleTitleForPath:', '- (void) refreshConsoleTitle'))

with tempfile.TemporaryDirectory() as work:
    work = Path(work)
    (work / 'TSWindowTitles.h').write_text(sources[TITLES])
    (work / 'main.m').write_text(PROGRAM.replace('METHODS', methods))
    binary = work / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-unused-variable', '-framework', 'Cocoa',
                    '-I', str(work), str(work / 'main.m'), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, end='', file=sys.stderr)
        sys.exit(1)
    checks += int(result.stdout.strip())

print(f'OK: {checks} checks')
