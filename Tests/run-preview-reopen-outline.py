#!/usr/bin/env python3
"""Check that the Preview drawer's outline leads to the new PDF after the Preview is shown again (#59).

When the Preview window was closed, or there was no PDF yet, reShowWithDocument: shows the new PDF through a short
branch of its own. The drawer's outline must then be rebuilt from the new PDF: its entries for the old PDF point to
pages of a document that is gone, so a click on them moved nothing.

The statements of that branch, setupOutline, the outline data source methods and takeDestinationFromOutline: run
unchanged in a PDFView subclass with a real NSOutlineView, without launching TeXShop. The PDFs, with an outline, are
read from PDF data, as after a typeset run. The entry for the page shown is marked in the new outline, also when the
page does not change, and, in a split Preview, when the second part is in use and gets its page back afterwards;
a cover page before the first entry gets no mark.
--mutation no-outline drops the new outline setup from the branch, no-mark the marking at its end, no-second-mark
the marking after the second part got its page back. The harness must then fail.
"""
import argparse
import os
import subprocess
import tempfile
from pathlib import Path
from production_fragments import closing_brace, method, verify_embedded
from source_tree import include_args, source_file

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['no-outline', 'no-mark', 'no-second-mark'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
signatures = ['- (void) setupOutline',
              '- (void)showActivePartInOutline',
              '- (void) showPageInOutline: (NSInteger) pageNumber',
              '- (IBAction) takeDestinationFromOutline: (id) sender',
              '- (NSInteger) outlineView: (NSOutlineView *) outlineView numberOfChildrenOfItem:',
              '- (id) outlineView: (NSOutlineView *) outlineView child:',
              '- (BOOL) outlineView: (NSOutlineView *) outlineView isItemExpandable:',
              '- (id) outlineView: (NSOutlineView *) outlineView objectValueForTableColumn:']
fragments = [('complete method: ' + s, source, method(source, s)) for s in signatures]
# reShowWithDocument: shows a new PDF this way after the Preview was closed, or when there was no PDF.
early_start = source.index('    if (self.myPDFWindow.noPdfFile  || self.myPDFWindow.previewClosed)\n')
early = source[early_start:closing_brace(source, source.index('{', early_start))]
fragments.append(('statements: reShowWithDocument: after the Preview was closed', source, early))
# The end of reShowForSecond, after the second part got its page back.
second_start = source.index('    // The outline may have been rebuilt while this part showed another page; when this part\n')
second_end = source.index('        [self showActivePartInOutline];\n', second_start) + len('        [self showActivePartInOutline];\n')
second = source[second_start:second_end]
fragments.append(('statements: reShowForSecond marks the entry of the part in use', source, second))
if args.mutation in ('no-outline', 'no-mark'):
    old = {'no-outline': '        [self setupOutline];\n', 'no-mark': '        [self showActivePartInOutline];\n'}[args.mutation]
    assert early.count(old) == 1
    early = early.replace(old, '')
if args.mutation == 'no-second-mark':
    second = ''
expansion = source_file(root, 'TSOutlineExpansion.m').read_text()

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSOutlineExpansion.h"
#define SUD [NSUserDefaults standardUserDefaults]
NSString *UseOutlineKey = @"UseOutline";
// The production code reaches the first part of the window as MyPDFKitView.
#define MyPDFKitView ReopenView

@interface PreviewWindowState : NSObject
@property BOOL noPdfFile, previewClosed;
@property (weak) PDFView *myPDFKitView, *activeView;
@end
@implementation PreviewWindowState
@end
@interface DocumentState : NSObject
@property NSInteger numberingCorrection;
@end
@implementation DocumentState
@end

@interface ReopenView : PDFView <NSOutlineViewDataSource> {
@public
    NSOutlineView *_outlineView;
    NSMutableArray *_searchResults;
    NSTableView *_searchTable;
    NSInteger totalPages;
    NSTextField *totalPage, *stotalPage, *totalPage1, *currentPage0, *scurrentPage, *currentPage1;
}
@property (strong) PreviewWindowState *myPDFWindow;
@property (strong) DocumentState *myDocument;
@property (strong) id sourceFiles;
@property (strong) PDFOutline *outline;
@property (strong) TSOutlineExpansion *outlineExpansion;
@property NSInteger setupRuns;
@property (weak) PDFView *secondPart;
@end

@implementation ReopenView
- (void)setup { self.setupRuns++; }
- (void)shareDocumentWithSecondView { if (self.secondPart) self.secondPart.document = self.document; }
- (void)keepPinnedLinkPreviewThroughMove {}
- (void)reShowEarlyWithDocument:(PDFDocument *)pdfDoc {
    PDFDocument *oldDoc; PDFPage *aPage;
EARLYBRANCH
}
- (void)secondPartRestored {
SECONDPART
}
METHODS
@end

static void check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
// Six pages; the outline has an entry for each page, and the fourth entry has two below it.
// With a cover, a page without an entry comes first.
static NSData *bookData(BOOL cover) {
    PDFDocument *document = [[PDFDocument alloc] init];
    NSInteger c = cover ? 1 : 0;
    for (NSInteger i = 0; i < 6 + c; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(300, 400)];
        [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, 300, 400)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    PDFOutline *top = [[PDFOutline alloc] init];
    for (NSInteger i = 0; i < 6; i++) {
        PDFOutline *entry = [[PDFOutline alloc] init];
        entry.label = [NSString stringWithFormat:@"Chapter %ld", (long)i + 1];
        entry.destination = [[PDFDestination alloc] initWithPage:[document pageAtIndex:i + c] atPoint:NSMakePoint(0, 400)];
        if (i == 3)
            for (NSInteger j = 0; j < 2; j++) {
                PDFOutline *sub = [[PDFOutline alloc] init];
                sub.label = [NSString stringWithFormat:@"Section %ld", (long)j + 1];
                sub.destination = [[PDFDestination alloc] initWithPage:[document pageAtIndex:4 + j + c] atPoint:NSMakePoint(0, 400)];
                [entry insertChild:sub atIndex:j];
            }
        [top insertChild:entry atIndex:i];
    }
    document.outlineRoot = top;
    return [document dataRepresentation];
}
static NSString *marked(ReopenView *v) {
    NSOutlineView *o = v->_outlineView;
    return o.selectedRow < 0 ? @"none" : [[o itemAtRow:o.selectedRow] label];
}
static NSInteger shownPage(PDFView *v) { return (NSInteger)[v.document indexForPage:v.currentPage]; }
static NSInteger rowOf(NSOutlineView *o, NSString *label) {
    for (NSInteger r = 0; r < o.numberOfRows; r++)
        if ([[[o itemAtRow:r] label] isEqualToString:label]) return r;
    return -1;
}
// A click on an entry of the drawer: the row is selected and the outline sends its action.
static void click(ReopenView *v, NSString *label) {
    NSOutlineView *o = v->_outlineView;
    NSInteger row = rowOf(o, label);
    check(row >= 0, [@"the outline shows " stringByAppendingString:label]);
    [o selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [o sendAction:o.action to:o.target];
}

static ReopenView *makePart(NSWindow *window, PreviewWindowState *state) {
    ReopenView *part = [[ReopenView alloc] initWithFrame:NSMakeRect(0, 0, 400, 500)];
    [window.contentView addSubview:part];
    part.displayMode = kPDFDisplaySinglePage;
    part.myPDFWindow = state;
    part.myDocument = [DocumentState new];
    return part;
}

// state: "closed" or "no PDF"; parts: "one", "split, first in use", "split, second in use".
static void run(NSString *state, NSString *parts, BOOL cover) {
    NSString *name = [NSString stringWithFormat:@"%@, %@%@: ", state, parts, cover ? @", cover" : @""];
    NSData *data = bookData(cover);
    NSInteger c = cover ? 1 : 0;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 500)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    PreviewWindowState *windowState = [PreviewWindowState new];
    ReopenView *v = makePart(window, windowState);
    windowState.myPDFKitView = v;
    windowState.activeView = v;
    ReopenView *second = nil;
    if (![parts isEqual:@"one"]) {
        second = makePart(window, windowState);
        v.secondPart = second;
        if ([parts hasSuffix:@"second in use"]) windowState.activeView = second;
    }
    NSOutlineView *o = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"label"];
    [o addTableColumn:column];
    o.outlineTableColumn = column;
    o.dataSource = v; o.target = v; o.action = @selector(takeDestinationFromOutline:);
    v->_outlineView = o;

    PDFDocument *first = [[PDFDocument alloc] initWithData:data];
    if ([state isEqual:@"closed"]) {
        v.document = first;
        second.document = first;
        [v setupOutline];
        click(v, @"Chapter 3");
        check(shownPage(v) == 2 + c, [name stringByAppendingString:@"before the Preview is closed, the drawer leads to page 3"]);
        check([marked(v) isEqual:@"Chapter 3"], [name stringByAppendingString:@"the entry clicked is marked"]);
        windowState.previewClosed = YES;
    } else {
        [v setupOutline];
        check(o.numberOfRows == 0, [name stringByAppendingString:@"with no PDF, the drawer is empty"]);
        windowState.noPdfFile = YES;
    }
    first = nil;
    // Typesetting, or Command-1, reads the PDF again into a new document.
    @autoreleasepool { [v reShowEarlyWithDocument:[[PDFDocument alloc] initWithData:data]]; }
    check(!windowState.previewClosed && !windowState.noPdfFile, [name stringByAppendingString:@"the new PDF is shown"]);
    check(v.setupRuns == ([state isEqual:@"no PDF"] ? 1 : 0), [name stringByAppendingString:@"a window without a PDF is set up"]);
    check(shownPage(v) == 0, [name stringByAppendingString:@"the new PDF starts at page 1"]);
    check(v.outline == v.document.outlineRoot, [name stringByAppendingString:@"the drawer shows the outline of the new PDF"]);
    check(o.numberOfRows == 6, [name stringByAppendingString:@"the drawer shows the six chapters"]);
    for (NSInteger r = 0; r < o.numberOfRows; r++)
        check([[o itemAtRow:r] destination].page.document == v.document,
              [name stringByAppendingString:@"every entry leads to a page of the new PDF"]);
    if (second) {
        // The second part gets its page back, page 5 of the book, without telling of a page change.
        check(second.document == v.document, [name stringByAppendingString:@"the second part shows the new PDF"]);
        [second goToPage:[second.document pageAtIndex:4 + c]];
        [second secondPartRestored];
    }
    NSString *expected = [parts hasSuffix:@"second in use"] ? @"Chapter 5" : (cover ? @"none" : @"Chapter 1");
    check([marked(v) isEqual:expected], [NSString stringWithFormat:@"%@the page of the part in use is marked: %@, not %@",
                                         name, expected, marked(v)]);
    click(v, @"Chapter 5");
    check(shownPage(v) == 4 + c, [name stringByAppendingString:@"a click on Chapter 5 shows page 5"]);
    [o expandItem:[o itemAtRow:rowOf(o, @"Chapter 4")]];
    click(v, @"Section 2");
    check(shownPage(v) == 5 + c, [name stringByAppendingString:@"a click on a section shows its page"]);
    click(v, @"Chapter 1");
    check(shownPage(v) == c, [name stringByAppendingString:@"a click on Chapter 1 goes back to its page"]);
    [window close];
}

int main(void) { @autoreleasepool {
    [SUD registerDefaults:@{@"UseOutline": @YES}];
    for (NSNumber *cover in @[@NO, @YES]) {
        run(@"closed", @"one", cover.boolValue);
        run(@"no PDF", @"one", cover.boolValue);
        run(@"closed", @"split, first in use", cover.boolValue);
        run(@"closed", @"split, second in use", cover.boolValue);
    }
    puts("PASS: after the Preview was closed and with no PDF before, the drawer leads to the pages of the new PDF and marks the page of the part in use");
} return 0; }
'''
program = program.replace('METHODS', '\n'.join(f for label, _, f in fragments if label.startswith('complete method:')))
program = program.replace('EARLYBRANCH', early).replace('SECONDPART', second)
verify_embedded(program, fragments if not args.mutation else [])
with tempfile.TemporaryDirectory(prefix='texshop-reopen-outline-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program)
    (temp / 'TSOutlineExpansion.m').write_text(expansion)
    subprocess.run(['xcrun', 'clang', '-mmacosx-version-min=14.6', '-w', '-fobjc-arc', '-framework', 'Cocoa',
                    '-framework', 'PDFKit', '-framework', 'Quartz', *include_args(root), str(temp / 'test.m'),
                    str(temp / 'TSOutlineExpansion.m'), '-o', str(temp / 'test')], check=True)
    home = temp / 'home'
    (home / 'Library' / 'Preferences').mkdir(parents=True)
    environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temp))
    result = subprocess.run([str(temp / 'test')], timeout=120, env=environment, capture_output=True, text=True)
    print(result.stdout, end='')
    if args.mutation:
        assert result.returncode != 0, f'mutation {args.mutation} was not detected'
        print(f'PASS: detected mutation {args.mutation}: {result.stderr.strip()}')
    else:
        print(result.stderr, end='')
        result.check_returncode()
