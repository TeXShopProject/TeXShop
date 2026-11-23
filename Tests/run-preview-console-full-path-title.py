#!/usr/bin/env python3
"""Check that the titles of the Preview window, the console and the Experiment windows follow
Show Full Path at once.

Every way of naming the Preview window (opening, typesetting, also in the single window, reading a
PDF changed outside TeXShop), the older image window for PDFs converted into a temporary folder,
the console and the Experiment panels goes through the document, which keeps the path shown.
Turning Show Full Path renames them all at once, a later update does not bring the file name back,
and a PDF opened by itself is named after the document's own file, also after moves. Pictures
opened by themselves keep the file name, as before. The test compiles the real TSWindowController
and the methods of TSDocument that name these windows into a small stand-in, with windows kept off screen and settings kept in memory."""
from pathlib import Path
import argparse
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
DOCUMENT = 'Sources/Document/TSDocument.m'
SCRAP = 'Sources/Document/TSDocument-Scrap.m'
JOBS = 'Sources/Typesetting/TSDocument-Jobs.m'
PREVIEW = 'Sources/Windows/TSPreviewWindow.m'
TITLES = 'Sources/Windows/TSWindowTitles.h'
CONTROLLER = 'Sources/Windows/TSWindowController.m'
CONSOLE = 'Sources/Typesetting/TSExperimentConsoleController.m'

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
    # Typesetting in the single window keeps the old path (first audit, 1).
    'single-window-keeps-old-path': (JOBS, '                    [self showPreviewTitleForPath: imagePath];\n                    if (! useFullSplitWindow) {\n',
                                     '                    if (! useFullSplitWindow) {\n                    [self showPreviewTitleForPath: imagePath];\n'),
    # A PDF opened by itself keeps its old path after a move (first audit, 2).
    'moved-pdf-keeps-old-path': (DOCUMENT, 'NSString *path = [self documentIsPDF] ? [url path] : self.previewTitlePath;',
                                 'NSString *path = self.previewTitlePath;'),
    # Reading a PDF opened by itself again goes to the PDF beside it with a lower-case extension (third audit).
    'refresh-reads-lower-case-pdf': (DOCUMENT, '\tif ([self documentIsPDF])\n\t\tpdfPath = [[self fileURL] path];\n\telse\n\t\tpdfPath =', '\tpdfPath ='),
    # Experiment takes the name the source window shows and strips it again (second audit, 2).
    'experiment-strips-shown-name': (SCRAP, 'title = [(showFullPath ? [url path] : [url lastPathComponent]) stringByDeletingPathExtension];',
                                     'title = [[textWindow title] stringByDeletingPathExtension];'),
    # The Experiment panels are not named again with the source window (first audit, 3).
    'experiment-not-renamed': (CONTROLLER, '        [(TSDocument *)document refreshExperimentTitles];\n', '        ;\n'),
    # The Experiment console keeps its first name (first audit, 3).
    'experiment-console-not-renamed': (SCRAP, '    [self.experimentConsole renameForSourceTitle: title];\n', ''),
    # A converted PDF in the older image window shows the file name (first audit, 4).
    'image-window-file-name-only': (DOCUMENT, '\t\t[pdfWindow setTitle: TSPreviewWindowTitle(self.imageTitlePath, showFullPath)];\n',
                                    '\t\t[pdfWindow setTitle: self.imageTitlePath.lastPathComponent];\n'),
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()

sources = {name: (root / name).read_text() for name in (DOCUMENT, SCRAP, JOBS, PREVIEW, TITLES, CONTROLLER, CONSOLE)}
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

def code(text):
    """The text without comments."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return '\n'.join(line for line in text.splitlines() if not line.strip().startswith('//'))

# Source checks: only the refresh methods name these windows.
document, scrap, jobs = sources[DOCUMENT], sources[SCRAP], sources[JOBS]
naming = {DOCUMENT: ('- (void) refreshPreviewTitle', '- (void) refreshConsoleTitle'),
          SCRAP: ('- (void) refreshExperimentTitles',)}
found = []
for path in sorted((root / 'Sources').rglob('*.m')):
    rel = str(path.relative_to(root))
    text = sources.get(rel, path.read_text())
    for signature in naming.get(rel, ()):
        text = text.replace(method(text, signature), '')
    # Pictures opened by themselves keep the file name, as before (second audit, 3).
    found += [f'{rel}: {line.strip()}' for line in code(text).splitlines()
              if re.search(r'\b(pdfKitWindow|outputWindow|pdfWindow|scrapWindow|scrapPDFWindow)\s+setTitle', line)
              and line.strip() != '[pdfWindow setTitle: [[[self fileURL] path] lastPathComponent]];']
check(not found, f'a window is named outside the document: {found[:1]}')
body = method(sources[PREVIEW], '- (void) becomeMainWindow')
check('[self.myDocument refreshPreviewTitle]' in body and 'setTitle' not in body,
      'the Preview window asks its document for the title when it comes to the front')
typeset = code(jobs)
check(typeset.count('[self showPreviewTitleForPath: imagePath];') == 1 and '[self showConsoleTitleForPath: imagePath];' in typeset
      and '[self showImageTitleForPath: imagePath];' in typeset,
      'typesetting names the Preview window, the image window and the console through the document')
start = typeset.index('[self showPreviewTitleForPath: imagePath];')
check(typeset.index('if (! useFullSplitWindow)', start - 200) > start,
      'typesetting names the Preview window also in the single window')
check(code(document).count('[self showPreviewTitleForPath:') >= 6 and '[self showImageTitleForPath:' not in code(document)
      and code(document).count('[pdfWindow setTitle: [[[self fileURL] path] lastPathComponent]];') == 2,
      'opening and updating name the Preview window through the document; pictures keep the file name')
body = method(document, '- (void)refreshPDFAndBringFront:(BOOL)front')
check('if ([self documentIsPDF])\n\t\tpdfPath = [[self fileURL] path];' in body,
      'a PDF opened by itself is read again from the document\'s own file')
body = method(document, '- (void)setFileURL:(NSURL *)url')
check('[self refreshPreviewTitle];' in body, 'a move of the document names a PDF opened by itself again')
check('[self refreshExperimentTitles];' in code(scrap).replace(method(scrap, '- (void) refreshExperimentTitles'), ''),
      'opening Experiment names its panels through the document')
console = sources[CONSOLE]
start_body = method(console, '- (void)startExecutable:')
rename = method(console, '- (void)renameForSourceTitle:')
check('self.sourceTitle = title;' in start_body and 'self.sourceTitle == nil' in rename,
      'the Experiment console is named again only after it has run')

STUB_DOCUMENT = r'''
#import <Cocoa/Cocoa.h>
@class TSWindowController;
@interface TestConsole : NSObject
@property (copy) NSString *sourceTitle;
- (void)renameForSourceTitle:(NSString *)title;
@end
@interface TSDocument : NSDocument {
@public
    BOOL showFullPath, fileIsTex;
    NSWindow *outputWindow, *pdfWindow, *textWindow;
    NSPanel *scrapWindow, *scrapPDFWindow;
}
@property (strong) NSWindow *pdfKitWindow;
@property (strong) TSWindowController *standardController;
@property (strong) TestConsole *experimentConsole;
@property (copy) NSString *previewTitlePath, *consoleTitlePath, *imageTitlePath;
- (BOOL) showsFullPath;
- (void) showPreviewTitleForPath: (NSString *)path;
- (void) showImageTitleForPath: (NSString *)path;
- (void) showConsoleTitleForPath: (NSString *)path;
- (void) refreshPreviewTitle;
- (void) refreshConsoleTitle;
- (void) refreshExperimentTitles;
- (void) changeShowFullPath: sender;
- (BOOL) documentIsPDF;
@end
'''

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "TSDocument.h"
#import "TSWindowController.h"
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
@implementation TestConsole
// As the Experiment console: named again only after it has run.
- (void)renameForSourceTitle:(NSString *)title { if (self.sourceTitle != nil) self.sourceTitle = title; }
@end
@implementation TSDocument
- (void) fixShowFullPathButton {}
- (BOOL) showsFullPath { return showFullPath; }
- (NSString *)fileType { return @"public.plain-text"; }
METHODS
@end
static NSWindow *offscreen(void) {
    // Never ordered front: the window stays off screen.
    return [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
}
static NSPanel *panel(void) {
    return [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
}
int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *folder = @"/Users/someone/a folder";
        NSString *source = [folder stringByAppendingPathComponent:@"sample.tex"];
        NSString *pdf = [folder stringByAppendingPathComponent:@"sample.pdf"];
        TSDocument *document = [[TSDocument alloc] init];
        document.fileURL = [NSURL fileURLWithPath:source];
        document.pdfKitWindow = offscreen();
        document->outputWindow = offscreen();
        document->pdfWindow = offscreen();
        document->scrapWindow = panel();
        document->scrapPDFWindow = panel();
        document.experimentConsole = [TestConsole new];
        TSWindowController *controller = [[TSWindowController alloc] initWithWindow:offscreen()];
        document->textWindow = controller.window;
        document.standardController = controller;
        [document addWindowController:controller];

        // Before a PDF is shown, the Preview window is named after the source file.
        document->showFullPath = YES;
        [document refreshPreviewTitle];
        check([document.pdfKitWindow.title isEqualToString:pdf], @"no PDF yet: the PDF path of the source file");

        // Switch off: file names. Experiment has opened and its console has run.
        document->showFullPath = NO;
        [controller synchronizeWindowTitleWithDocumentName];
        [document showPreviewTitleForPath:pdf];
        [document showConsoleTitleForPath:pdf];
        [document showImageTitleForPath:pdf];
        document.experimentConsole.sourceTitle = document->scrapWindow.title;
        check([document.pdfKitWindow.title isEqualToString:@"sample.pdf"], @"switch off: the Preview window shows the file name");
        check([document->outputWindow.title isEqualToString:@"sample console"], @"switch off: the console shows the file name");
        check([document->pdfWindow.title isEqualToString:@"sample.pdf"], @"switch off: the image window shows the file name");
        check([document->scrapWindow.title isEqualToString:@"sample"] && [document->scrapPDFWindow.title isEqualToString:@"sample"],
              @"switch off: the Experiment panels show the file name");

        // Turning the switch on renames all at once.
        [document changeShowFullPath:nil];
        NSString *fullName = [folder stringByAppendingPathComponent:@"sample"];
        check(document->showFullPath, @"the switch is on");
        check([[TestDefaults shared].values[ShowFullPathEnabledKey] boolValue], @"the setting is saved");
        check([document->textWindow.title isEqualToString:source], @"switch on: the source window shows the full path");
        check([document.pdfKitWindow.title isEqualToString:pdf], @"switch on: the Preview window shows the full path at once");
        check([document->outputWindow.title isEqualToString:[fullName stringByAppendingString:@" console"]], @"switch on: the console shows the full path at once");
        check([document->pdfWindow.title isEqualToString:pdf], @"switch on: the image window shows the full path at once");
        check([document->scrapWindow.title isEqualToString:fullName] && [document->scrapPDFWindow.title isEqualToString:fullName],
              @"switch on: the Experiment panels show the full path at once");
        check([document.experimentConsole.sourceTitle isEqualToString:fullName], @"switch on: the Experiment console is named again at once");

        // A PDF changed outside TeXShop, a new typesetting, a converted PDF: still the full path.
        [document showPreviewTitleForPath:pdf];
        [document showConsoleTitleForPath:pdf];
        [document showImageTitleForPath:pdf];
        check([document.pdfKitWindow.title isEqualToString:pdf], @"after an update: the Preview window keeps the full path");
        check([document->outputWindow.title isEqualToString:[fullName stringByAppendingString:@" console"]], @"after typesetting: the console keeps the full path");
        check([document->pdfWindow.title isEqualToString:pdf], @"after a conversion: the image window keeps the full path");

        // A PDF typeset from the source keeps the path it was read from after the source moves.
        NSString *other = @"/Users/someone/out/other name.pdf";
        [document showPreviewTitleForPath:other];
        document.fileURL = [NSURL fileURLWithPath:@"/Users/someone/b/renamed.tex"];
        [document refreshPreviewTitle];
        check([document.pdfKitWindow.title isEqualToString:other], @"the title is the path of the PDF shown");

        // Turning the switch off renames all at once.
        [document changeShowFullPath:nil];
        check([document.pdfKitWindow.title isEqualToString:@"other name.pdf"], @"switch off: the Preview window shows the file name at once");
        check([document->outputWindow.title isEqualToString:@"sample console"], @"switch off: the console shows the file name at once");
        check([document->scrapWindow.title isEqualToString:@"renamed"], @"switch off: the Experiment panels show the file name at once");
        check([document.experimentConsole.sourceTitle isEqualToString:@"renamed"], @"switch off: the Experiment console is named again at once");

        // A PDF opened by itself is named after the document's own file, also when an update reads it
        // under another case of its extension, and after moves (second audit, 1).
        TSDocument *alone = [[TSDocument alloc] init];
        alone.fileURL = [NSURL fileURLWithPath:@"/Users/someone/Mixed.PDF"];
        alone.pdfKitWindow = offscreen();
        alone->showFullPath = YES;
        [alone showPreviewTitleForPath:@"/Users/someone/Mixed.pdf"];
        check([alone.pdfKitWindow.title isEqualToString:@"/Users/someone/Mixed.PDF"], @"a PDF opened by itself: the document's own file");
        alone.fileURL = [NSURL fileURLWithPath:@"/Users/someone/moved/Second.pdf"];
        [alone refreshPreviewTitle];
        check([alone.pdfKitWindow.title isEqualToString:@"/Users/someone/moved/Second.pdf"], @"a PDF opened by itself follows a move after an update");
        [alone showPreviewTitleForPath:@"/Users/someone/moved/Second.pdf"];
        alone.fileURL = [NSURL fileURLWithPath:@"/Users/someone/Third.pdf"];
        [alone refreshPreviewTitle];
        check([alone.pdfKitWindow.title isEqualToString:@"/Users/someone/Third.pdf"], @"a PDF opened by itself follows a second move");

        // Experiment keeps every dot of the file name but the extension, and an untitled document's name (second audit, 2).
        TSDocument *chapter = [[TSDocument alloc] init];
        chapter.fileURL = [NSURL fileURLWithPath:@"/Users/someone/book/chapter.01.tex"];
        chapter->fileIsTex = YES;
        chapter->scrapWindow = panel();
        // The source window as AppKit names it when the extension is hidden.
        chapter->textWindow = offscreen();
        chapter->textWindow.title = @"chapter.01";
        chapter.experimentConsole = [TestConsole new];
        chapter.experimentConsole.sourceTitle = @"old";
        [chapter refreshExperimentTitles];
        check([chapter->scrapWindow.title isEqualToString:@"chapter.01"] && [chapter.experimentConsole.sourceTitle isEqualToString:@"chapter.01"],
              @"Experiment: the file name without its extension");
        chapter->showFullPath = YES;
        [chapter refreshExperimentTitles];
        check([chapter->scrapWindow.title isEqualToString:@"/Users/someone/book/chapter.01"], @"Experiment: the full path without the extension");
        TSDocument *untitled = [[TSDocument alloc] init];
        untitled->scrapWindow = panel();
        [untitled refreshExperimentTitles];
        check([untitled->scrapWindow.title isEqualToString:untitled.displayName], @"Experiment of an untitled document: its name");

        // A console never used for typesetting, and an Experiment console that never ran, keep their titles.
        TSDocument *fresh = [[TSDocument alloc] init];
        fresh->outputWindow = offscreen();
        fresh->outputWindow.title = @"Console";
        fresh.experimentConsole = [TestConsole new];
        fresh->showFullPath = YES;
        [fresh refreshConsoleTitle];
        [fresh refreshPreviewTitle];
        [fresh refreshExperimentTitles];
        check([fresh->outputWindow.title isEqualToString:@"Console"], @"untitled: the console keeps its title");
        check(fresh.experimentConsole.sourceTitle == nil, @"an Experiment console that never ran is not named");
        printf("%lu\n", (unsigned long)checks);
    }
    return 0;
}
'''

methods = ''.join(method(document, signature) for signature in (
    '- (BOOL) documentIsPDF', '- (void) changeShowFullPath: sender', '- (void) showPreviewTitleForPath:', '- (void) showImageTitleForPath:',
    '- (void) refreshPreviewTitle', '- (void) showConsoleTitleForPath:', '- (void) refreshConsoleTitle'))
methods += method(scrap, '- (void) refreshExperimentTitles')

with tempfile.TemporaryDirectory() as work:
    work = Path(work)
    (work / 'TSDocument.h').write_text(STUB_DOCUMENT)
    (work / 'globals.h').write_text('')
    (work / 'TSWindowTitles.h').write_text(sources[TITLES])
    (work / 'TSWindowController.h').write_text((root / 'Sources/Windows/TSWindowController.h').read_text())
    (work / 'TSWindowController.m').write_text(sources[CONTROLLER])
    (work / 'main.m').write_text(PROGRAM.replace('METHODS', methods))
    binary = work / 'test'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-unused-variable', '-framework', 'Cocoa',
                    '-I', str(work), str(work / 'TSWindowController.m'), str(work / 'main.m'), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)], capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, end='', file=sys.stderr)
        sys.exit(1)
    checks += int(result.stdout.strip())

print(f'OK: {checks} checks')
