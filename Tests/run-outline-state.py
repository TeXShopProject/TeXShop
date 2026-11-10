#!/usr/bin/env python3
"""Check that the Preview drawer keeps its open outline items and scroll position when the outline is replaced.

The production methods of MyPDFKitView that rebuild the outline run unchanged against a real NSOutlineView, without
launching TeXShop. Each outline is read from PDF data, as after a typeset run. A typeset run delivers new PDFOutline
objects for the same headings, so open items are matched by their labels.
--mutation no-restore skips the expansion step. The harness must then fail.
"""
import argparse
import os
import subprocess
import tempfile
from pathlib import Path
from production_fragments import method, verify_embedded

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['no-restore'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Preview/MyPDFKitView.m').read_text(encoding='latin1')
signatures = ['- (void) collectOpenOutlineKeysUnder:',
              '- (void) expandOutlineItemsUnder:', '- (void) scrollOutlineTo:', '- (void) setupOutline',
              '- (NSInteger) outlineView: (NSOutlineView *) outlineView numberOfChildrenOfItem:',
              '- (id) outlineView: (NSOutlineView *) outlineView child:',
              '- (BOOL) outlineView: (NSOutlineView *) outlineView isItemExpandable:',
              '- (id) outlineView: (NSOutlineView *) outlineView objectValueForTableColumn:']
fragments = [method(source, signature) for signature in signatures]
methods = '\n'.join(fragments)
if args.mutation == 'no-restore':
    old = '[self expandOutlineItemsUnder: self.outline prefix: @"" withKeys: openKeys];'
    assert methods.count(old) == 1
    methods = methods.replace(old, '')
program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#define SUD [NSUserDefaults standardUserDefaults]
NSString *UseOutlineKey = @"UseOutline";

@interface OutlineHarness : NSObject <NSOutlineViewDataSource> {
    NSOutlineView *_outlineView;
}
@property (retain) PDFOutline *outline;
@property (strong) PDFDocument *shownDocument;
- (void)attach:(NSOutlineView *)view;
- (PDFDocument *)document;
@end

@implementation OutlineHarness
- (void)attach:(NSOutlineView *)view { _outlineView = view; view.dataSource = self; }
- (PDFDocument *)document { return self.shownDocument; }
METHODS
@end

static void check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static PDFPage *firstPage;
static PDFOutline *node(NSString *label, NSArray *children) {
    PDFOutline *outline = [[PDFOutline alloc] init];
    outline.label = label;
    outline.destination = [[PDFDestination alloc] initWithPage:firstPage atPoint:NSMakePoint(0, 700)];
    for (NSUInteger i = 0; i < children.count; i++) [outline insertChild:children[i] atIndex:i];
    return outline;
}
// Four chapters, the last with the same label as the first. Each has sections S1 to S3 with two subsections.
static PDFDocument *book(BOOL extraFirstSectionInChapter2, BOOL withoutChapter2) {
    NSMutableArray *chapters = [NSMutableArray array];
    firstPage = [[PDFPage alloc] init];
    NSArray *names = @[@"Intro", @"Methods", @"Results", @"Intro"];
    for (NSUInteger c = 0; c < names.count; c++) {
        if (withoutChapter2 && c == 1) continue;
        NSMutableArray *sections = [NSMutableArray array];
        if (extraFirstSectionInChapter2 && c == 1) [sections addObject:node(@"S0", @[])];
        for (NSString *label in @[@"S1", @"S2", @"S3"])
            [sections addObject:node(label, @[node(@"a", @[]), node(@"b", @[])])];
        [chapters addObject:node(names[c], sections)];
    }
    PDFDocument *document = [[PDFDocument alloc] init];
    [document insertPage:firstPage atIndex:0];
    document.outlineRoot = node(@"", chapters);
    // Read the outline back from PDF data, as TeXShop does after a typeset run.
    document = [[PDFDocument alloc] initWithData:[document dataRepresentation]];
    check([[document outlineRoot] numberOfChildren] == chapters.count, @"the fixture outline survives as PDF data");
    return document;
}
// Replace the document as a reload does, and keep no reference of our own to the previous one.
static void show(OutlineHarness *h, PDFDocument *(^make)(void)) {
    @autoreleasepool { h.shownDocument = make(); }
}
static PDFOutline *chapter(OutlineHarness *h, NSUInteger i) { return [h.outline childAtIndex:i]; }
static PDFOutline *section(OutlineHarness *h, NSUInteger c, NSUInteger s) { return [chapter(h, c) childAtIndex:s]; }
static NSOutlineView *view(OutlineHarness *h) { return [h valueForKey:@"_outlineView"]; }
static BOOL isOpen(OutlineHarness *h, PDFOutline *item) { return [view(h) isItemExpanded:item]; }
static OutlineHarness *makeHarness(NSScrollView **scroll) {
    OutlineHarness *h = [[OutlineHarness alloc] init];
    NSOutlineView *table = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"label"];
    [table addTableColumn:column];
    table.outlineTableColumn = column;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    scrollView.documentView = table;
    [h attach:table];
    if (scroll) *scroll = scrollView;
    return h;
}

int main(void) { @autoreleasepool {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UseOutline": @YES}];

    // First load, no outline at all, and an outline appearing later: nothing to restore, nothing may crash.
    NSScrollView *scroll = nil;
    OutlineHarness *h = makeHarness(&scroll);
    [h setupOutline];
    show(h, ^{ return [[PDFDocument alloc] init]; });
    [h setupOutline];
    show(h, ^{ return book(NO, NO); });
    [h setupOutline];
    check([view(h) numberOfRows] == 4, @"a new outline starts with the four chapters closed");

    // Open items and the scroll position survive a replaced outline.
    [view(h) expandItem:chapter(h, 1)];
    [view(h) expandItem:section(h, 1, 0)];
    [view(h) expandItem:chapter(h, 2)];
    [view(h) expandItem:chapter(h, 3)];
    NSClipView *clip = scroll.contentView;
    check(NSHeight(clip.documentRect) > NSHeight(clip.bounds) + 40, @"the fixture outline must be taller than the view");
    [clip scrollToPoint:NSMakePoint(0, 40)];
    [scroll reflectScrolledClipView:clip];
    NSInteger rows = [view(h) numberOfRows];
    check(clip.bounds.origin.y == 40, @"the fixture scrolls by 40 points");

    show(h, ^{ return book(NO, NO); });
    PDFOutline *oldChapter = chapter(h, 1);
    [h setupOutline];
    check(chapter(h, 1) != oldChapter, @"the new outline is made of new objects");
    check(!isOpen(h, chapter(h, 0)), @"the first Intro stays closed");
    check(isOpen(h, chapter(h, 1)), @"Methods stays open");
    check(isOpen(h, section(h, 1, 0)), @"S1 in Methods stays open");
    check(!isOpen(h, section(h, 1, 1)), @"S2 in Methods stays closed");
    check(isOpen(h, chapter(h, 2)), @"Results stays open");
    check(isOpen(h, chapter(h, 3)), @"the second Intro, with the label of the first, stays open");
    check([view(h) numberOfRows] == rows, @"the same rows are visible");
    check(clip.bounds.origin.y == 40, @"the outline keeps its scroll position");

    // Of two chapters with the same label, only the open one stays open.
    [view(h) collapseItem:chapter(h, 1)];
    [view(h) collapseItem:chapter(h, 2)];
    [view(h) collapseItem:chapter(h, 3)];
    [view(h) expandItem:chapter(h, 3)];
    show(h, ^{ return book(NO, NO); });
    [h setupOutline];
    check(!isOpen(h, chapter(h, 0)), @"the first of two chapters with one label stays closed");
    check(isOpen(h, chapter(h, 3)), @"the second of two chapters with one label stays open");

    // A section added before an open one does not move the open state to another section.
    [view(h) expandItem:chapter(h, 1)];
    [view(h) expandItem:section(h, 1, 1)];
    show(h, ^{ return book(YES, NO); });
    [h setupOutline];
    check(isOpen(h, chapter(h, 1)), @"Methods stays open when a section is added");
    check([[section(h, 1, 2) label] isEqualToString:@"S2"] && isOpen(h, section(h, 1, 2)), @"S2 stays open under its new index");
    check(!isOpen(h, section(h, 1, 0)) && !isOpen(h, section(h, 1, 1)), @"the new S0 and S1 stay closed");

    // A chapter that disappears leaves the others as they were.
    [view(h) expandItem:chapter(h, 2)];
    show(h, ^{ return book(NO, YES); });
    [h setupOutline];
    check([h.outline numberOfChildren] == 3, @"the outline has three chapters");
    check(isOpen(h, chapter(h, 1)) && [[chapter(h, 1) label] isEqualToString:@"Results"], @"Results stays open");

    // An outline that disappears empties the view.
    show(h, ^{ return [[PDFDocument alloc] init]; });
    [h setupOutline];
    check([view(h) numberOfRows] == 0, @"no outline, no rows");

    puts("PASS: open items, duplicate labels, added and removed headings, scroll position, empty outline");
} return 0; }
'''
program = program.replace('METHODS', methods)
verify_embedded(program, [('complete method: ' + signature, source, fragment)
                          for signature, fragment in zip(signatures, fragments)]
                if not args.mutation else [])
with tempfile.TemporaryDirectory(prefix='texshop-outline-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-mmacosx-version-min=14.6', '-w', '-fobjc-arc', '-framework', 'Cocoa',
                    '-framework', 'PDFKit', str(temp / 'test.m'), '-o', str(temp / 'test')], check=True)
    home = temp / 'home'
    (home / 'Library' / 'Preferences').mkdir(parents=True)
    environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home))
    subprocess.run([str(temp / 'test')], check=True, timeout=120, env=environment)
