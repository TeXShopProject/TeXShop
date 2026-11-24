#!/usr/bin/env python3
"""Resolution-1.0 ink for Fit to Content Width (#62).

Synthetic PDFs are generated while the probe runs. Core Graphics and PDFKit must agree within
one page point on each edge. A borderless link may use the background measurement; a popup,
highlight, ink mark, bordered link or unknown annotation may not. The three benchmark PDFs
stay outside this repository.
"""
from pathlib import Path
import argparse, os, subprocess, sys, tempfile
from source_tree import include_args

MUTATIONS = {
    'gray-not-ink': ('if (line[column] < 240)', 'if (line[column] < 200)'),
    # The bitmap is the requested box, so deleting the clip still leaves outside ink off the
    # bitmap. Measuring the media box instead pulls that ink in. Both box arguments change.
    'crop-includes-outside': ('(CGPDFBox)box', 'kCGPDFMediaBox'),
    'corner-flipped': ('(height - 1 - maxY)', 'minY'),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mutation', choices=sorted(MUTATIONS))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

program = r'''
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#import "TSContentWidth.h"
#import "TSContentZoom.h"

static NSUInteger checks;
static void check(BOOL ok, NSString *message) {
    checks++;
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

@interface PDFBuf : NSObject
@property (strong) NSMutableData *data;
@property (strong) NSMutableArray<NSNumber *> *offsets;
@end
@implementation PDFBuf
- (instancetype)init {
    self = [super init];
    _data = [NSMutableData dataWithData:[@"%PDF-1.4\n" dataUsingEncoding:NSASCIIStringEncoding]];
    _offsets = [NSMutableArray array];
    return self;
}
- (NSUInteger)add:(NSString *)body {
    NSUInteger number = self.offsets.count + 1;
    [self.offsets addObject:@(self.data.length)];
    NSString *object = [NSString stringWithFormat:@"%lu 0 obj\n%@\nendobj\n", (unsigned long)number, body];
    [self.data appendData:[object dataUsingEncoding:NSASCIIStringEncoding]];
    return number;
}
- (NSData *)finish {
    NSUInteger xref = self.data.length;
    NSMutableString *table = [NSMutableString stringWithFormat:@"xref\n0 %lu\n0000000000 65535 f \n", (unsigned long)self.offsets.count + 1];
    for (NSNumber *offset in self.offsets)
        [table appendFormat:@"%010ld 00000 n \n", offset.longValue];
    [table appendFormat:@"trailer\n<< /Size %lu /Root 1 0 R >>\nstartxref\n%lu\n%%%%EOF\n",
        (unsigned long)self.offsets.count + 1, (unsigned long)xref];
    [self.data appendData:[table dataUsingEncoding:NSASCIIStringEncoding]];
    return self.data;
}
@end

static NSData *pdfPages(NSArray<NSDictionary *> *pages) {
    PDFBuf *buf = [PDFBuf new];
    [buf add:@"<< /Type /Catalog /Pages 2 0 R >>"];
    NSMutableString *kids = [NSMutableString string];
    for (NSUInteger i = 0; i < pages.count; i++)
        [kids appendFormat:@"%lu 0 R ", (unsigned long)(3 + i * 2)];
    [buf add:[NSString stringWithFormat:@"<< /Type /Pages /Kids [%@] /Count %lu >>", kids, (unsigned long)pages.count]];
    for (NSDictionary *page in pages) {
        NSString *extra = page[@"extra"] ?: @"";
        [buf add:[NSString stringWithFormat:@"<< /Type /Page /Parent 2 0 R /MediaBox %@ /CropBox %@ /Rotate %ld /Contents %lu 0 R /Resources << >> %@ >>",
            page[@"media"], page[@"crop"] ?: page[@"media"], [page[@"rotate"] integerValue],
            (unsigned long)buf.offsets.count + 2, extra]];
        NSString *stream = page[@"stream"] ?: @"";
        [buf add:[NSString stringWithFormat:@"<< /Length %lu >>\nstream\n%@\nendstream",
            (unsigned long)stream.length + 1, stream]];
    }
    return buf.finish;
}

// A one-page PDF whose only annotation is written into the file, not added afterwards.
static NSData *pdfAnnotated(NSString *annotation, NSString *extra) {
    PDFBuf *buf = [PDFBuf new];
    [buf add:@"<< /Type /Catalog /Pages 2 0 R >>"];
    [buf add:@"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"];
    [buf add:@"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R /Resources << >> /Annots [5 0 R] >>"];
    NSString *stream = @"0 g\n30 20 40 30 re f";
    [buf add:[NSString stringWithFormat:@"<< /Length %lu >>\nstream\n%@\nendstream", (unsigned long)stream.length + 1, stream]];
    [buf add:annotation];
    if (extra) [buf add:extra];
    return buf.finish;
}

static BOOL near(CGFloat value, CGFloat expected) { return fabs(value - expected) <= 1.0; }
static BOOL sameRect(NSRect a, NSRect b) {
    return near(a.origin.x, b.origin.x) && near(a.origin.y, b.origin.y) && near(NSMaxX(a), NSMaxX(b)) && near(NSMaxY(a), NSMaxY(b));
}
static NSString *rectString(NSRect r) {
    return [NSString stringWithFormat:@"(%.2f,%.2f %.2fx%.2f)", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

static void checkInk(NSString *name, PDFPage *page, CGPDFPageRef cg, PDFDisplayBox box, BOOL expectInk, NSRect expected) {
    NSRect kit = NSZeroRect, cgInk = NSZeroRect;
    TSContentInkStatus kitStatus = TSContentInkMeasure(page, box, 1.0, &kit);
    TSContentInkStatus cgStatus = TSContentInkMeasureCG(cg, box, 1.0, &cgInk);
    BOOL kitBlank = kitStatus == TSContentInkBlank, cgBlank = cgStatus == TSContentInkBlank;
    check(kitStatus != TSContentInkFailed && cgStatus != TSContentInkFailed, [name stringByAppendingString:@" draws"]);
    check(kitBlank == cgBlank && (kitBlank || sameRect(kit, cgInk)),
          [NSString stringWithFormat:@"%@ Core Graphics %@ PDFKit %@", name, rectString(cgInk), rectString(kit)]);
    if (expectInk)
        check(kitStatus == TSContentInkFound && sameRect(kit, expected),
              [NSString stringWithFormat:@"%@ %@ wanted %@", name, rectString(kit), rectString(expected)]);
    else
        check(kitBlank && cgBlank, [name stringByAppendingString:@" is blank"]);
    NSRect old = TSContentInkBoundsAt(page, box, 1.0);
    check(NSIsEmptyRect(old) == kitBlank && (kitBlank || NSEqualRects(old, kit)), [name stringByAppendingString:@" matches the zoom measurement"]);
}

@interface TSExternalPDFDocument : PDFDocument
@property (copy) NSString *snapshotDirectory;
@end
@interface ProbeView : PDFView
@property NSUInteger later;
@end
@implementation ProbeView
- (void)measureContentLater { self.later++; }
@end

static PDFDocument *cloneAt(NSString *root, NSString *name, NSData *data, NSMutableArray *keep) {
    NSString *directory = [root stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"snapshot.pdf"]];
    [data writeToURL:url atomically:YES];
    TSExternalPDFDocument *document = [[TSExternalPDFDocument alloc] initWithURL:url];
    document.snapshotDirectory = directory;
    [keep addObject:document];
    return document;
}

static TSContentWidthResult finish(ProbeView *view) {
    __block TSContentWidthResult result = (TSContentWidthResult)-1;
    BOOL started = TSContentWidthScheduleFast(view, ^(TSContentWidthResult next) { result = next; });
    check(started, @"a background measurement starts");
    for (int i = 0; i < 300 && result < 0; i++)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(result >= 0, @"the background measurement finishes");
    return result;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        [NSApplication sharedApplication];
        NSData *data = pdfPages(@[
            @{@"media": @"[0 0 200 100]", @"rotate": @0, @"stream": @"0 g\n10 20 30 40 re f"},
            @{@"media": @"[0 0 200 100]", @"rotate": @0, @"stream": @""},
            @{@"media": @"[0 0 180 240]", @"rotate": @90, @"stream": @"0 g\n12 18 25 36 re f"},
            @{@"media": @"[0 0 180 240]", @"rotate": @180, @"stream": @"0 g\n12 18 25 36 re f"},
            @{@"media": @"[0 0 180 240]", @"rotate": @270, @"stream": @"0 g\n12 18 25 36 re f"},
            @{@"media": @"[0 0 220 400]", @"crop": @"[15 25 180 300]", @"rotate": @90, @"stream": @"0 g\n4 6 8 8 re f\n0 g\n40 60 50 70 re f"},
            @{@"media": @"[-80 -40 120 160]", @"rotate": @0, @"stream": @"0 g\n-10 20 30 25 re f"},
            @{@"media": @"[100 80 280 260]", @"rotate": @0, @"stream": @"0 g\n130 110 40 50 re f"},
            @{@"media": @"[0 0 200 300]", @"crop": @"[30 40 170 250]", @"rotate": @0, @"stream": @"0 g\n5 5 10 10 re f\n0 g\n50 70 40 30 re f"},
            @{@"media": @"[0 0 120 80]", @"rotate": @0, @"stream": @"0 g\n0 0 1 80 re f"},
            @{@"media": @"[0 0 50 40]", @"rotate": @0, @"stream": @"0 g\n49 39 1 1 re f"},
            @{@"media": @"[0 0 80 60]", @"rotate": @0, @"stream": @"0.9372549 g\n10 10 40 30 re f"},
            @{@"media": @"[0 0 80 60]", @"rotate": @0, @"stream": @"0.9411765 g\n10 10 40 30 re f"},
            @{@"media": @"[0 0 4500 90]", @"rotate": @0, @"stream": @"0 g\n100 15 30 20 re f"},
            @{@"media": @"[0 0 200 80]", @"rotate": @0, @"stream": @"0 g\n10 10 40 20 re f"},
            @{@"media": @"[0 0 200 80]", @"rotate": @0, @"stream": @"0 g\n150 10 40 20 re f"},
            @{@"media": @"[0 0 595 842]", @"rotate": @0, @"stream": @"0 g\n107 150 200 400 re f"},
            @{@"media": @"[0 0 842 1191]", @"rotate": @0, @"stream": @"0 g\n80 90 300 500 re f"},
        ]);
        NSString *path = [root stringByAppendingPathComponent:@"pages.pdf"];
        [data writeToFile:path atomically:YES];
        PDFDocument *document = [[PDFDocument alloc] initWithData:data];
        CGPDFDocumentRef cg = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path]);
        check(document.pageCount == 18 && CGPDFDocumentGetNumberOfPages(cg) == 18, @"the synthetic PDF opens");
        NSArray *names = @[@"black", @"blank", @"rot90", @"rot180", @"rot270", @"rot90-crop", @"negative", @"shifted",
            @"crop", @"edge", @"corner", @"gray239", @"gray240", @"long", @"left", @"right", @"a4", @"a3"];
        NSArray *expect = @[
            @[@YES, [NSValue valueWithRect:NSMakeRect(10, 20, 30, 40)]], @[@NO],
            @[@YES, [NSValue valueWithRect:NSMakeRect(12, 18, 25, 36)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(12, 18, 25, 36)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(12, 18, 25, 36)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(40, 60, 50, 70)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(-10, 20, 30, 25)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(130, 110, 40, 50)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(50, 70, 40, 30)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(0, 0, 1, 80)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(49, 39, 1, 1)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(10, 10, 40, 30)]], @[@NO],
            @[@YES, [NSValue valueWithRect:NSMakeRect(100, 15, 30, 20)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(10, 10, 40, 20)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(150, 10, 40, 20)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(107, 150, 200, 400)]],
            @[@YES, [NSValue valueWithRect:NSMakeRect(80, 90, 300, 500)]],
        ];
        for (NSUInteger i = 0; i < names.count; i++) {
            BOOL ink = [expect[i][0] boolValue];
            checkInk(names[i], [document pageAtIndex:i], CGPDFDocumentGetPage(cg, i + 1), kPDFDisplayBoxCropBox,
                     ink, ink ? [expect[i][1] rectValue] : NSZeroRect);
        }
        NSRect media = NSZeroRect;
        TSContentInkMeasure([document pageAtIndex:8], kPDFDisplayBoxMediaBox, 1.0, &media);
        check(near(media.origin.x, 5) && near(media.origin.y, 5), @"the media box keeps ink outside the crop");
        CGPDFDocumentRelease(cg);

        check(TSContentWidthMeasureAll(document, kPDFDisplayBoxCropBox), @"every page is stored");
        check(TSContentWidthIsComplete(document, kPDFDisplayBoxCropBox), @"the store is complete");
        BOOL known = NO;
        NSRect blank = TSContentWidthRawInk(document, kPDFDisplayBoxCropBox, [document pageAtIndex:1], &known);
        check(known && NSIsEmptyRect(blank), @"a blank page is stored and empty");
        NSInteger generation = TSContentWidthGeneration(document);
        TSContentWidthNoteAnnotationChange(document);
        check(TSContentWidthGeneration(document) == generation + 1 && !TSContentWidthIsComplete(document, kPDFDisplayBoxCropBox),
              @"an annotation change drops the stored ink");
        TSContentWidthRecordFailure(document, kPDFDisplayBoxCropBox);
        check(TSContentWidthHasFailure(document, kPDFDisplayBoxCropBox), @"a failed measurement is recorded");
        TSContentWidthNoteAnnotationChange(document);
        check(!TSContentWidthHasFailure(document, kPDFDisplayBoxCropBox), @"the next generation can be measured");
        PDFDocument *empty = [PDFDocument new];
        check(!TSContentWidthIsComplete(empty, kPDFDisplayBoxCropBox) && !TSContentWidthHasFailure(empty, kPDFDisplayBoxCropBox),
              @"a document with no pages is not measured and not a failure");
        ProbeView *plain = [ProbeView new];
        plain.document = document;
        check(!TSContentWidthScheduleFast(plain, nil), @"a document opened from memory stays on PDFKit");

        NSMutableArray *keep = [NSMutableArray array];
        NSData *plainPage = pdfPages(@[@{@"media": @"[0 0 200 100]", @"rotate": @0, @"stream": @"0 g\n10 20 30 40 re f"}]);
        PDFDocument *fast = cloneAt(root, @"fast", plainPage, keep);
        ProbeView *view = [ProbeView new];
        view.displayBox = kPDFDisplayBoxCropBox;
        view.document = fast;
        TSContentWidthWatch(view);
        check(finish(view) == TSContentWidthResultReady && TSContentWidthIsComplete(fast, kPDFDisplayBoxCropBox),
              @"the clone is measured off the main thread");
        known = NO;
        NSRect stored = TSContentWidthRawInk(fast, kPDFDisplayBoxCropBox, [fast pageAtIndex:0], &known);
        check(known && sameRect(stored, NSMakeRect(10, 20, 30, 40)), @"the background result is the raw ink");

        ProbeView *other = [ProbeView new];
        other.displayBox = kPDFDisplayBoxCropBox;
        other.document = fast;
        TSContentWidthWatch(other);
        __block NSUInteger ready = 0;
        check(TSContentWidthScheduleFast(view, ^(TSContentWidthResult result) { if (result == TSContentWidthResultReady) ready++; }), @"the first view joins");
        check(TSContentWidthScheduleFast(other, ^(TSContentWidthResult result) { if (result == TSContentWidthResultReady) ready++; }), @"the second view joins the same job");
        for (int i = 0; i < 300 && ready < 2; i++)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        check(ready == 2, @"both views hear the same result");

        PDFDocument *stale = cloneAt(root, @"stale", plainPage, keep);
        ProbeView *staleView = [ProbeView new];
        staleView.displayBox = kPDFDisplayBoxCropBox;
        staleView.document = stale;
        __block TSContentWidthResult staleResult = (TSContentWidthResult)-1;
        check(TSContentWidthScheduleFast(staleView, ^(TSContentWidthResult result) { staleResult = result; }), @"a job can be cancelled");
        TSContentWidthNoteAnnotationChange(stale);
        for (int i = 0; i < 300 && staleResult < 0; i++)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        check(staleResult == TSContentWidthResultRetry && !TSContentWidthIsComplete(stale, kPDFDisplayBoxCropBox),
              @"a cancelled job writes nothing");

        PDFDocument *turned = cloneAt(root, @"turned", plainPage, keep);
        TSContentWidthNoteDrawingDiverged(turned);
        ProbeView *turnedView = [ProbeView new];
        turnedView.document = turned;
        check(TSContentWidthDrawingDiverged(turned) && !TSContentWidthScheduleFast(turnedView, nil),
              @"after the pages are turned the clone stays on PDFKit");

        NSDictionary *annotations = @{
            @"link": @"<< /Type /Annot /Subtype /Link /Rect [1 1 12 12] /Border [0 0 0] >>",
            @"border": @"<< /Type /Annot /Subtype /Link /Rect [1 1 12 12] /BS << /W 1 >> /Border [0 0 1] >>",
            @"appearance": @"<< /Type /Annot /Subtype /Link /Rect [1 1 12 12] /Border [0 0 0] /AP << /N 6 0 R >> >>",
            @"popup": @"<< /Type /Annot /Subtype /Popup /Rect [1 1 20 20] >>",
            @"highlight": @"<< /Type /Annot /Subtype /Highlight /Rect [1 1 20 12] /QuadPoints [1 12 20 12 1 1 20 1] >>",
            @"ink": @"<< /Type /Annot /Subtype /Ink /Rect [1 1 20 12] /InkList [[1 1 12 8]] >>",
            @"unknown": @"<< /Type /Annot /Subtype /Foo /Rect [1 1 20 12] >>",
        };
        for (NSString *name in @[@"link", @"border", @"appearance", @"popup", @"highlight", @"ink", @"unknown"]) {
            NSString *extra = [name isEqualToString:@"appearance"] ?
                @"<< /Type /XObject /Subtype /Form /BBox [0 0 12 12] /Length 19 >>\nstream\n0 g\n0 0 12 12 re f\nendstream" : nil;
            PDFDocument *annotated = cloneAt(root, name, pdfAnnotated(annotations[name], extra), keep);
            ProbeView *annotatedView = [ProbeView new];
            annotatedView.displayBox = kPDFDisplayBoxCropBox;
            annotatedView.document = annotated;
            BOOL started = TSContentWidthScheduleFast(annotatedView, nil);
            BOOL allow = [name isEqualToString:@"link"];
            check(started == allow, [NSString stringWithFormat:@"%@ %@ the background measurement", name, allow ? @"uses" : @"stays off"]);
            if (allow) {
                __block TSContentWidthResult result = (TSContentWidthResult)-1;
                // The call above already joined a job without a callback. Ask again and wait.
                TSContentWidthScheduleFast(annotatedView, ^(TSContentWidthResult next) { result = next; });
                for (int i = 0; i < 300 && result < 0; i++)
                    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
                known = NO;
                NSRect ink = TSContentWidthRawInk(annotated, kPDFDisplayBoxCropBox, [annotated pageAtIndex:0], &known);
                check(result == TSContentWidthResultReady && known && sameRect(ink, NSMakeRect(30, 20, 40, 30)),
                      @"a borderless link leaves the ink unchanged");
            }
        }
        printf("PASS: %lu checks\n", (unsigned long)checks);
        return 0;
    }
}
'''

with tempfile.TemporaryDirectory(dir='/private/tmp') as temp:
    temp = Path(temp)
    home = temp / 'home'
    work = temp / 'work'
    home.mkdir()
    work.mkdir()
    source = (root / 'Sources/Preview/TSContentWidth.m').read_text()
    if args.mutation:
        old, new = MUTATIONS[args.mutation]
        found = source.count(old)
        expect = 2 if args.mutation == 'crop-includes-outside' else 1
        assert found == expect, f'{args.mutation}: found {found}, wanted {expect}'
        source = source.replace(old, new)
    (temp / 'TSContentWidth.m').write_text(source)
    (temp / 'test.m').write_text(program)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'Quartz', '-framework', 'PDFKit',
                    '-I', str(root / 'Tests'), *include_args(root), str(temp / 'test.m'), str(temp / 'TSContentWidth.m'),
                    str(root / 'Sources/Preview/TSExternalPDFSnapshot.m'), '-o', str(temp / 'test')], check=True)
    env = dict(os.environ, HOME=str(home), CFFIXED_USER_HOME=str(home), TMPDIR=str(work) + '/')
    result = subprocess.run([str(temp / 'test'), str(work)], capture_output=True, text=True, env=env, timeout=120)
    output = result.stdout + result.stderr
    if args.mutation:
        assert result.returncode != 0, 'mutation not detected: ' + args.mutation + '\n' + output
        print('PASS: detected mutation ' + args.mutation + ': ' + output.strip().splitlines()[-1])
    else:
        print(output.strip())
        sys.exit(result.returncode)
