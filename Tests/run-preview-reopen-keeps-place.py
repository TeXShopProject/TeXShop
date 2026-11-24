#!/usr/bin/env python3
"""Check that Command-1 shows a closed Preview again at its place (#70).

Up to 6.00 RC2, Command-1 read the PDF again when the Preview window was closed, and reShowWithDocument: then showed
page 1, because previewClosed was still set; the pinned popups were gone as well. Now a closed Preview whose PDF has
not changed since it was read is only ordered front, so it keeps its place, its pinned popups and its drawer. A PDF
changed in the meantime is read with previewClosed cleared, so that the place is kept, as after typesetting; if the
PDF cannot be shown, previewClosed is set again, so that a later typeset run still starts at page 1.

bringPdfWindowFront, closedPreviewShowsPDFOnDisk and previewPDFPath run unchanged in a stand-in document with a
real PDFView and real files; refreshPDFAndBringFront: is recorded instead of reading the PDF, and the window is a
stand-in that is never shown.
notePDFLoadedAtPath: and externalPDFPath run unchanged as well: the state of the file is noted also for a PDF
with a password, which shows no pages while it is locked, and not for a file that changed while it was read.
--mutation always-reload reads the PDF also when it has not changed, ignores-change never reads it again,
reload-from-top reads a changed PDF with previewClosed still set, closed-flag-lost leaves previewClosed cleared
after a reload that showed nothing, ignores-missing-pdf counts a Preview without a PDF as showing the file,
locked-not-noted notes no state for a locked PDF, locked-not-shown reads a locked PDF again,
changed-on-load-noted notes the state of a file that changed while it was read.
The harness must then fail.
"""
import argparse
import os
import subprocess
import tempfile
from pathlib import Path
from production_fragments import method, verify_embedded
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=['always-reload', 'ignores-change', 'reload-from-top', 'closed-flag-lost',
                                           'ignores-missing-pdf', 'locked-not-noted', 'locked-not-shown',
                                           'changed-on-load-noted'])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/Document/TSDocument.m').read_text(encoding='utf-8')
signatures = ['- (void)bringPdfWindowFront{', '- (BOOL)closedPreviewShowsPDFOnDisk', '- (NSString *)previewPDFPath',
              '- (void)notePDFLoadedAtPath:(NSString *)path signature:(NSString *)signature changeTime:(NSString *)changeTime\n{',
              '- (NSString *)externalPDFPath\n{']
fragments = [('complete method: ' + s, source, method(source, s)) for s in signatures]
mutations = {
    'always-reload': (1, '\treturn signature && ', '\treturn NO && signature && '),
    'ignores-change': (1, '[signature isEqualToString: self.shownPDFSignature]', 'YES'),
    'reload-from-top': (0, '\t\t\t\tself.pdfKitWindow.previewClosed = NO;\n\t\t\t\t[self refreshPDFAndBringFront: YES];',
                        '\t\t\t\t[self refreshPDFAndBringFront: YES];'),
    'closed-flag-lost': (0, '\t\t\t\tif (![self.pdfKitWindow isVisible])\n\t\t\t\t\tself.pdfKitWindow.previewClosed = YES;\n', ''),
    'ignores-missing-pdf': (1, ' && !self.pdfKitWindow.noPdfFile && self.myPDFKitView.document != nil', ''),
    # The first audit: a locked PDF, which has no pages until it is unlocked, left no signature, and Command-1
    # read it again, which showed nothing.
    'locked-not-noted': (3, '    BOOL unchanged = signature && ', '    BOOL unchanged = signature && self.myPDFKitView.document.pageCount && '),
    'locked-not-shown': (1, ' && self.myPDFKitView.document != nil', ' && self.myPDFKitView.document.pageCount > 0'),
    'changed-on-load-noted': (3, '    self.shownPDFSignature = unchanged ? signature : nil;', '    self.shownPDFSignature = signature;'),
}
texts = [f for _, _, f in fragments]
if args.mutation:
    index, old, new = mutations[args.mutation]
    assert texts[index].count(old) == 1, args.mutation
    texts[index] = texts[index].replace(old, new)

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSExternalPDFReload.h"
#define RootForSwitchWindow 3

// Activating TeXShop is recorded; the harness never becomes the active application.
@interface StandInApplication : NSObject
+ (instancetype)sharedApplication;
@property NSInteger activations;
- (void)activateIgnoringOtherApps:(BOOL)flag;
@end
@implementation StandInApplication
+ (instancetype)sharedApplication { static StandInApplication *app; if (!app) app = [self new]; return app; }
- (void)activateIgnoringOtherApps:(BOOL)flag { if (flag) self.activations++; }
@end
#define NSApplication StandInApplication

// The Preview window: ordering it front clears previewClosed, as TSPreviewWindow does.
@interface StandInPreviewWindow : NSObject
@property (getter=isVisible) BOOL visible;
@property BOOL previewClosed, noPdfFile;
@property NSInteger frontings;
@end
@implementation StandInPreviewWindow
- (void)makeKeyAndOrderFront:(id)sender { self.visible = YES; self.previewClosed = NO; self.frontings++; }
@end

@interface StandInText : NSObject
@property (copy) NSString *string;
@end
@implementation StandInText
@end

@interface ReopenDocument : NSObject {
@public
    BOOL _externalEditor;
}
@property (strong) StandInPreviewWindow *pdfKitWindow;
@property (strong) PDFView *myPDFKitView;
@property (copy) NSString *shownPDFSignature, *externalPDFPendingSignature;
@property NSInteger externalPDFGeneration, accepted;
@property (strong) NSURL *fileURL;
@property BOOL documentIsPDF, readingShowsPDF;
@property NSInteger reloads;
@property BOOL closedAtReload;
@end

@implementation ReopenDocument
- (StandInText *)textView { StandInText *t = [StandInText new]; t.string = @"\\documentclass{article}"; return t; }
- (BOOL)checkMasterFile:(NSString *)text forTask:(NSInteger)task { return NO; }
- (BOOL)checkRootFile_forTask:(NSInteger)task { return NO; }
- (BOOL)fromKit { return YES; }
// The PDF with pages is also taken for the external reloads; it is only counted here.
- (void)acceptExternalPDFAtPath:(NSString *)path signature:(NSString *)signature changeTime:(NSString *)changeTime
                        document:(PDFDocument *)document { self.accepted++; }
// Reading the PDF again: recorded, with the state it starts from. The Preview is shown when the PDF can be read.
- (void)refreshPDFAndBringFront:(BOOL)front {
    self.reloads++;
    self.closedAtReload = self.pdfKitWindow.previewClosed;
    if (self.readingShowsPDF) [self.pdfKitWindow makeKeyAndOrderFront:self];
}
METHODS
@end

static void check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
// PDFKit counts the pages of the PDF it writes with a password while it is locked; it counts none in a PDF
// whose cross-reference table is compressed, as the reporter's of #55, until it is unlocked.
@interface CompressedLockedPDF : PDFDocument
@end
@implementation CompressedLockedPDF
- (NSUInteger)pageCount { return self.isLocked ? 0 : [super pageCount]; }
@end
static NSData *pdfData(NSInteger pages);
static NSData *lockedData(void) {
    PDFDocument *document = [[PDFDocument alloc] initWithData:pdfData(6)];
    NSDictionary *options = @{PDFDocumentUserPasswordOption: @"secret", PDFDocumentOwnerPasswordOption: @"owner"};
    NSString *file = [NSProcessInfo.processInfo.environment[@"TS_TEST_DIR"] stringByAppendingPathComponent:@"lock.tmp"];
    [document writeToFile:file withOptions:options];
    NSData *data = [NSData dataWithContentsOfFile:file];
    [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
    return data;
}
static NSData *pdfData(NSInteger pages) {
    PDFDocument *document = [[PDFDocument alloc] init];
    for (NSInteger i = 0; i < pages; i++) {
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(300, 400)];
        [image lockFocus]; [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0, 0, 300, 400)); [image unlockFocus];
        [document insertPage:[[PDFPage alloc] initWithImage:image] atIndex:i];
    }
    return [document dataRepresentation];
}

// A document whose Preview was closed while it showed page 4 of its PDF; a locked PDF is left
// locked, or unlocked before, as the user does in the Preview.
static ReopenDocument *closedPreviewOf(NSString *directory, NSString *name, BOOL isPDF, int lock) {
    ReopenDocument *d = [ReopenDocument new];
    d.documentIsPDF = isPDF;
    d.fileURL = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
    NSString *pdf = isPDF ? d.fileURL.path : [[d.fileURL.path stringByDeletingPathExtension] stringByAppendingPathExtension:@"pdf"];
    if (!isPDF) [@"\\documentclass{article}" writeToURL:d.fileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [(lock ? lockedData() : pdfData(6)) writeToFile:pdf atomically:YES];
    d.pdfKitWindow = [StandInPreviewWindow new];
    d.myPDFKitView = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
    d.myPDFKitView.displayMode = kPDFDisplaySinglePage;
    // Read as reShowWithPath: does: the state of the file is taken first, and noted after the PDF is shown.
    NSString *signature = TSExternalPDFSignature(pdf);
    Class kind = lock ? [CompressedLockedPDF class] : [PDFDocument class];
    d.myPDFKitView.document = [[kind alloc] initWithData:[NSData dataWithContentsOfFile:pdf]];
    [d notePDFLoadedAtPath:pdf signature:signature changeTime:nil];
    check(d.shownPDFSignature != nil && [d.shownPDFSignature isEqual:signature], @"fixture: the state of the file read is noted");
    check(d.accepted == (lock ? 0 : 1), @"fixture: only a PDF with pages is taken for the external reloads");
    if (lock) {
        check(d.myPDFKitView.document.isLocked && d.myPDFKitView.document.pageCount == 0, @"fixture: a locked PDF shows no pages");
        if (lock == 2)
            check([d.myPDFKitView.document unlockWithPassword:@"secret"] && d.myPDFKitView.document.pageCount == 6,
                  @"fixture: the PDF is unlocked");
    }
    if (d.myPDFKitView.document.pageCount)
        [d.myPDFKitView goToPage:[d.myPDFKitView.document pageAtIndex:3]];
    d.pdfKitWindow.previewClosed = YES;
    d.readingShowsPDF = YES;
    return d;
}
static ReopenDocument *closedPreview(NSString *directory, NSString *name, BOOL isPDF) {
    return closedPreviewOf(directory, name, isPDF, 0);
}
static NSInteger shownPage(ReopenDocument *d) {
    return (NSInteger)[d.myPDFKitView.document indexForPage:d.myPDFKitView.currentPage];
}
static void rewrite(NSString *pdf) {
    [pdfData(7) writeToFile:pdf atomically:YES];
    // Another second, so that the change shows on file systems that keep whole seconds.
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:2]}
                                     ofItemAtPath:pdf error:nil];
}

int main(void) { @autoreleasepool {
    NSString *directory = NSProcessInfo.processInfo.environment[@"TS_TEST_DIR"];
    StandInApplication *app = [StandInApplication sharedApplication];

    // The PDF has not changed: the Preview comes back as it was closed.
    ReopenDocument *d = closedPreview(directory, @"book.tex", NO);
    PDFDocument *shown = d.myPDFKitView.document;
    [d bringPdfWindowFront];
    check(d.reloads == 0, @"unchanged PDF: the PDF is not read again");
    check(d.pdfKitWindow.visible && d.pdfKitWindow.frontings == 1 && app.activations == 1,
          @"unchanged PDF: TeXShop is activated and the Preview is ordered front");
    check(!d.pdfKitWindow.previewClosed, @"unchanged PDF: the Preview is no longer closed");
    check(d.myPDFKitView.document == shown && shownPage(d) == 3, @"unchanged PDF: the Preview shows page 4, as before it was closed");

    // Command-1 on a Preview that is open only brings it front.
    [d bringPdfWindowFront];
    check(d.reloads == 0 && d.pdfKitWindow.frontings == 2 && app.activations == 1, @"open Preview: ordered front only");

    // The PDF changed while the Preview was closed: it is read again with previewClosed cleared, so that
    // reShowWithDocument: keeps the place.
    d = closedPreview(directory, @"changed.tex", NO);
    rewrite([directory stringByAppendingPathComponent:@"changed.pdf"]);
    [d bringPdfWindowFront];
    check(d.reloads == 1, @"changed PDF: the PDF is read again");
    check(!d.closedAtReload, @"changed PDF: read with previewClosed cleared, so the place is kept");
    check(d.pdfKitWindow.visible && !d.pdfKitWindow.previewClosed, @"changed PDF: the Preview is shown");

    // A changed PDF that cannot be read yet: the Preview stays closed and a later typeset run starts at page 1.
    d = closedPreview(directory, @"unreadable.tex", NO);
    rewrite([directory stringByAppendingPathComponent:@"unreadable.pdf"]);
    d.readingShowsPDF = NO;
    [d bringPdfWindowFront];
    check(d.reloads == 1 && !d.closedAtReload, @"unreadable PDF: reading is tried at the place left");
    check(!d.pdfKitWindow.visible && d.pdfKitWindow.previewClosed, @"unreadable PDF: the Preview stays closed and previewClosed is set again");

    // The PDF was removed: nothing on disk matches, so it is read as before.
    d = closedPreview(directory, @"removed.tex", NO);
    [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:@"removed.pdf"] error:nil];
    d.readingShowsPDF = NO;
    [d bringPdfWindowFront];
    check(d.reloads == 1 && d.pdfKitWindow.previewClosed && !d.pdfKitWindow.visible, @"removed PDF: read as before, the Preview stays closed");

    // No PDF was shown yet: the Preview is set up by reading the PDF.
    d = closedPreview(directory, @"new.tex", NO);
    d.myPDFKitView.document = nil;
    d.pdfKitWindow.noPdfFile = YES;
    [d bringPdfWindowFront];
    check(d.reloads == 1, @"no PDF shown yet: the PDF is read");

    // A PDF opened by itself, with the extension in capitals: its own file counts.
    d = closedPreview(directory, @"Paper.PDF", YES);
    [d bringPdfWindowFront];
    check(d.reloads == 0 && d.pdfKitWindow.visible && shownPage(d) == 3, @"PDF document: its own file is unchanged, the Preview comes back as it was");
    d = closedPreview(directory, @"Changed.PDF", YES);
    rewrite(d.fileURL.path);
    [d bringPdfWindowFront];
    check(d.reloads == 1 && !d.closedAtReload, @"PDF document: a changed file is read at the place left");

    // A PDF with a password, unlocked before the Preview was closed: shown again unlocked, at its place.
    d = closedPreviewOf(directory, @"unlocked.tex", NO, 2);
    shown = d.myPDFKitView.document;
    [d bringPdfWindowFront];
    check(d.reloads == 0 && d.pdfKitWindow.visible && d.myPDFKitView.document == shown && !shown.isLocked && shownPage(d) == 3,
          @"unlocked PDF: shown again unlocked at page 4, without reading it again");
    // Still locked: shown again as it was, asking for the password, since reading it again shows nothing.
    d = closedPreviewOf(directory, @"locked.tex", NO, 1);
    [d bringPdfWindowFront];
    check(d.reloads == 0 && d.pdfKitWindow.visible, @"locked PDF: the Preview is shown again");
    // A PDF that changed while it was read: its state is not taken for the PDF shown.
    d = closedPreview(directory, @"during.tex", NO);
    NSString *during = [directory stringByAppendingPathComponent:@"during.pdf"];
    NSString *before = TSExternalPDFSignature(during);
    rewrite(during);
    [d notePDFLoadedAtPath:during signature:before changeTime:nil];
    check(d.shownPDFSignature == nil, @"PDF changed while it was read: no state is noted");
    [d bringPdfWindowFront];
    check(d.reloads == 1, @"PDF changed while it was read: Command-1 reads it again");

    // An external editor has no Preview of TeXShop's to bring front.
    d = closedPreview(directory, @"external.tex", NO);
    d->_externalEditor = YES;
    [d bringPdfWindowFront];
    check(d.reloads == 0 && !d.pdfKitWindow.visible, @"external editor: nothing happens");

    puts("PASS: Command-1 shows a closed Preview again at its place, reading the PDF only when it changed");
} return 0; }
'''
program = program.replace('METHODS', '\n'.join(texts))
verify_embedded(program, fragments if not args.mutation else [])
with tempfile.TemporaryDirectory(prefix='texshop-reopen-place-') as directory:
    temp = Path(directory)
    (temp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-mmacosx-version-min=14.6', '-w', '-fobjc-arc', '-framework', 'Cocoa',
                    '-framework', 'PDFKit', '-framework', 'Quartz', *include_args(root), str(temp / 'test.m'),
                    '-o', str(temp / 'test')], check=True)
    home = temp / 'home'
    (home / 'Library' / 'Preferences').mkdir(parents=True)
    files = temp / 'files'
    files.mkdir()
    environment = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(temp), TS_TEST_DIR=str(files))
    result = subprocess.run([str(temp / 'test')], timeout=120, env=environment, capture_output=True, text=True)
    print(result.stdout, end='')
    if args.mutation:
        assert result.returncode != 0, f'mutation {args.mutation} was not detected'
        print(f'PASS: detected mutation {args.mutation}: {result.stderr.strip()}')
    else:
        print(result.stderr, end='')
        result.check_returncode()
