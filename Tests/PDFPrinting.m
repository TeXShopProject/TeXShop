// Prints a PDF of mixed pages (/Rotate 90 and 270, landscape, small and large) to a PDF file
// with the operation of a print from the Preview, without a panel, and measures each printed
// page: the blue frame gives where and how large the page lands, the red arrow which way
// the page's top points. Usage: probe input.pdf output-directory
#import <Cocoa/Cocoa.h>
#import "TestAppKitIsolation.h"
#import "TSPDFPrinting.h"

static int failures;
static void Check(BOOL condition, NSString *message)
{
    printf("%s: %s\n", condition ? "ok" : "FAIL", message.UTF8String);
    if (! condition) failures++;
}

typedef struct { NSRect frame; NSString *arrow; } PrintedPage;

@interface SummaryWatcher : NSObject
@property NSInteger count;
@end
@implementation SummaryWatcher
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context { self.count++; }
@end

// Renders a printed page at one pixel per point and finds the frame and the arrow.
static PrintedPage Measure(CGPDFPageRef page)
{
    CGRect box = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
    size_t w = (size_t)ceil(box.size.width), h = (size_t)ceil(box.size.height);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, w, h));
    CGContextTranslateCTM(context, -box.origin.x, -box.origin.y);
    CGContextDrawPDFPage(context, page);
    const uint8_t *pixels = CGBitmapContextGetData(context);
    NSInteger minX = w, minY = h, maxX = -1, maxY = -1, rMinX = w, rMinY = h, rMaxX = -1, rMaxY = -1;
    double rx = 0, ry = 0, rn = 0;
    for (size_t row = 0; row < h; row++)
        for (size_t x = 0; x < w; x++) {
            const uint8_t *p = pixels + row * w * 4 + x * 4;
            NSInteger y = (NSInteger)(h - 1 - row); // PDF coordinates: y upward
            if (p[2] > 150 && p[0] < 100 && p[1] < 100) {
                minX = MIN(minX, (NSInteger)x); maxX = MAX(maxX, (NSInteger)x); minY = MIN(minY, y); maxY = MAX(maxY, y);
            } else if (p[0] > 150 && p[1] < 100 && p[2] < 100) {
                rMinX = MIN(rMinX, (NSInteger)x); rMaxX = MAX(rMaxX, (NSInteger)x); rMinY = MIN(rMinY, y); rMaxY = MAX(rMaxY, y);
                rx += x; ry += y; rn++;
            }
        }
    CGContextRelease(context);
    PrintedPage result = { NSMakeRect(minX, minY, maxX - minX + 1, maxY - minY + 1), @"none" };
    if (maxX < 0) result.frame = NSZeroRect;
    if (rn > 0) {
        // The centroid of a triangle lies toward its base: the apex is on the other side.
        double dx = rx / rn - (rMinX + rMaxX) / 2.0, dy = ry / rn - (rMinY + rMaxY) / 2.0;
        result.arrow = fabs(dx) > fabs(dy) ? (dx < 0 ? @"right" : @"left") : (dy < 0 ? @"up" : @"down");
    }
    return result;
}

// The paper of the next print is landscape A4; the print starts from this print info if set.
static BOOL ExpectLandscape;
static NSPrintInfo *StartInfo;
static NSPrintOperation *LastOperation;

static NSPrintInfo *A4Info(NSString *output)
{
    NSPrintInfo *info = [[NSPrintInfo alloc] initWithDictionary:@{}];
    info.paperSize = NSMakeSize(595.276, 841.89); // A4
    info.jobDisposition = NSPrintSaveJob;
    info.dictionary[NSPrintJobSavingURL] = [NSURL fileURLWithPath:output];
    return info;
}

static NSArray<NSValue *> *Print(NSString *input, NSString *output, void (^choose)(TSPDFPrintAccessory *), NSArray<NSString *> **arrows)
{
    NSPrintInfo *info = StartInfo ?: A4Info(output);
    if (StartInfo) info.dictionary[NSPrintJobSavingURL] = [NSURL fileURLWithPath:output];
    NSDictionary *before = [info.dictionary copy];
    NSPaperOrientation orientationBefore = info.orientation;
    PDFDocument *document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:input]];
    NSPrintOperation *operation = TSPDFPrintOperation(document, info);
    LastOperation = operation;
    Check([info.dictionary isEqual:before] && info.orientation == orientationBefore, @"making the operation leaves the document's print info as it is");
    TSPDFPrintAccessory *accessory = (TSPDFPrintAccessory *)operation.printPanel.accessoryControllers.firstObject;
    Check([accessory isKindOfClass:TSPDFPrintAccessory.class], @"the print panel has the section");
    Check(! (operation.printPanel.options & NSPrintPanelShowsScaling), @"the panel's own Scale field is left out");
    [accessory view];
    if (choose) choose(accessory);
    operation.showsPrintPanel = NO;
    operation.showsProgressPanel = NO;
    Check([operation runOperation], @"the operation prints");
    CGPDFDocumentRef printed = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:output]);
    NSMutableArray *frames = [NSMutableArray array], *directions = [NSMutableArray array];
    for (size_t i = 1; printed && i <= CGPDFDocumentGetNumberOfPages(printed); i++) {
        CGPDFPageRef page = CGPDFDocumentGetPage(printed, i);
        CGRect media = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
        NSSize paper = media.size;
        if ((CGPDFPageGetRotationAngle(page) / 90) % 2) paper = NSMakeSize(paper.height, paper.width);
        NSSize a4 = ExpectLandscape ? NSMakeSize(841.89, 595.276) : NSMakeSize(595.276, 841.89);
        Check(fabs(paper.width - a4.width) < 1.5 && fabs(paper.height - a4.height) < 1.5,
              [NSString stringWithFormat:@"%@ page %zu is %@ A4 (%@)", output.lastPathComponent, i, ExpectLandscape ? @"landscape" : @"portrait", NSStringFromSize(paper)]);
        PrintedPage measured = Measure(page);
        [frames addObject:[NSValue valueWithRect:measured.frame]];
        [directions addObject:measured.arrow];
    }
    if (printed) CGPDFDocumentRelease(printed);
    *arrows = directions;
    return frames;
}

// The frame is upright (portrait) or lying (landscape), and within the paper.
static void CheckPage(NSArray<NSValue *> *frames, NSArray<NSString *> *arrows, NSUInteger i, NSString *arrow, BOOL portrait, NSSize exact, NSString *what)
{
    if (i >= frames.count) { Check(NO, [NSString stringWithFormat:@"%@: page %lu printed", what, i + 1]); return; }
    NSRect f = frames[i].rectValue;
    Check([arrows[i] isEqual:arrow], [NSString stringWithFormat:@"%@: page %lu points %@ (printed %@)", what, i + 1, arrow, arrows[i]]);
    Check((f.size.height > f.size.width) == portrait, [NSString stringWithFormat:@"%@: page %lu %@ (frame %@)", what, i + 1, portrait ? @"upright" : @"lying", NSStringFromRect(f)]);
    if (exact.width > 0)
        Check(fabs(f.size.width - exact.width) < 3 && fabs(f.size.height - exact.height) < 3,
              [NSString stringWithFormat:@"%@: page %lu at actual size %@ (frame %@)", what, i + 1, NSStringFromSize(exact), NSStringFromRect(f)]);
    else {
        // Fitted: the page fills the paper's width or height to its printable margins.
        BOOL fills = f.size.width > 0.85 * 595 || f.size.height > 0.85 * 842;
        Check(fills && f.size.width <= 596 && f.size.height <= 843, [NSString stringWithFormat:@"%@: page %lu fits the paper (frame %@)", what, i + 1, NSStringFromRect(f)]);
    }
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        TSInstallAppKitIsolation();
        [NSApplication sharedApplication];
        NSString *input = @(argv[1]), *dir = @(argv[2]);
        NSArray *arrows;
        const CGFloat mm = 72 / 25.4;
        NSSize b5 = NSMakeSize(174 * mm, 247 * mm), b5Lying = NSMakeSize(247 * mm, 174 * mm);

        // First print: as Preview, turned to suit the paper and fitted to it.
        __block BOOL defaultRotate = NO, defaultFit = NO;
        NSArray *frames = Print(input, [dir stringByAppendingPathComponent:@"default.pdf"], ^(TSPDFPrintAccessory *a) {
            defaultRotate = a.autoRotate; defaultFit = a.scaleToFit;
        }, &arrows);
        Check(defaultRotate && defaultFit, @"Auto Rotate and Scale to Fit are chosen at first");
        NSString *w = @"rotate+fit";
        CheckPage(frames, arrows, 0, @"up", YES, NSZeroSize, w);      // 174x247 mm portrait
        CheckPage(frames, arrows, 1, @"up", YES, NSZeroSize, w);      // /Rotate 90: shown lying, turned back
        CheckPage(frames, arrows, 2, @"down", YES, NSZeroSize, w);    // /Rotate 270: shown lying, turned the same way
        CheckPage(frames, arrows, 3, @"left", YES, NSZeroSize, w);    // landscape page turned on the paper
        CheckPage(frames, arrows, 4, @"up", YES, NSZeroSize, w);      // small page enlarged
        CheckPage(frames, arrows, 5, @"up", YES, NSZeroSize, w);      // A3 /Rotate 90 reduced and turned
        Check(NSWidth([frames[4] rectValue]) > 100 * mm * 1.5, @"the small page is enlarged");

        // Auto Rotate off: each page as shown in the Preview, fitted.
        frames = Print(input, [dir stringByAppendingPathComponent:@"fit.pdf"], ^(TSPDFPrintAccessory *a) {
            NSButton *box = (NSButton *)[((NSStackView *)a.view).views firstObject];
            [box performClick:nil];
        }, &arrows);
        w = @"fit";
        CheckPage(frames, arrows, 0, @"up", YES, NSZeroSize, w);
        CheckPage(frames, arrows, 1, @"right", NO, NSZeroSize, w);
        CheckPage(frames, arrows, 2, @"left", NO, NSZeroSize, w);
        CheckPage(frames, arrows, 3, @"up", NO, NSZeroSize, w);

        // Scale 100%, Auto Rotate on: actual size, lying pages turned.
        __block NSString *summary = nil;
        frames = Print(input, [dir stringByAppendingPathComponent:@"actual.pdf"], ^(TSPDFPrintAccessory *a) {
            NSStackView *row = (NSStackView *)((NSStackView *)a.view).views[1];
            [(NSButton *)row.views[0] performClick:nil];
            summary = [[a.localizedSummaryItems valueForKey:NSPrintPanelAccessorySummaryItemDescriptionKey] componentsJoinedByString:@","];
        }, &arrows);
        Check([summary hasSuffix:@",100%"], [NSString stringWithFormat:@"the summary gives the scale (%@)", summary]);
        w = @"rotate+100%";
        CheckPage(frames, arrows, 0, @"up", YES, b5, w);
        CheckPage(frames, arrows, 1, @"up", YES, b5, w);
        CheckPage(frames, arrows, 3, @"left", YES, b5, w);
        CheckPage(frames, arrows, 4, @"up", YES, NSMakeSize(100 * mm, 140 * mm), w);

        // Scale 50% typed in the field, Auto Rotate off.
        frames = Print(input, [dir stringByAppendingPathComponent:@"half.pdf"], ^(TSPDFPrintAccessory *a) {
            [(NSButton *)[((NSStackView *)a.view).views firstObject] performClick:nil];
            NSStackView *row = (NSStackView *)((NSStackView *)a.view).views[1];
            [(NSButton *)row.views[0] performClick:nil];
            NSTextField *field = (NSTextField *)row.views[1];
            Check(field.enabled, @"the Scale field is available with Scale chosen");
            field.stringValue = @"50";
            [field sendAction:field.action to:field.target];
            field.stringValue = @"";
            [field sendAction:field.action to:field.target];
            Check(a.scalePercent == 50 && field.integerValue == 50, [NSString stringWithFormat:@"an emptied Scale field goes back to 50%% (%ld)", (long)a.scalePercent]);
        }, &arrows);
        w = @"50%";
        CheckPage(frames, arrows, 1, @"right", NO, NSMakeSize(b5Lying.width / 2, b5Lying.height / 2), w);
        CheckPage(frames, arrows, 5, @"right", NO, NSMakeSize(420 * mm / 2, 297 * mm / 2), w);

        // The summary the print panel watches changes with each choice.
        {
            NSPrintInfo *info = A4Info([dir stringByAppendingPathComponent:@"unused.pdf"]);
            TSPDFPrintAccessory *a = [[TSPDFPrintAccessory alloc] initWithPrintInfo:info];
            [a view];
            SummaryWatcher *watcher = [SummaryWatcher new];
            [a addObserver:watcher forKeyPath:@"localizedSummaryItems" options:0 context:NULL];
            a.autoRotate = NO; Check(watcher.count == 1, @"the summary changes with Auto Rotate");
            a.scaleToFit = NO; Check(watcher.count == 2, @"the summary changes with Scale or Scale to Fit");
            a.scalePercent = 70; Check(watcher.count == 3, @"the summary changes with the scale");
            [a removeObserver:watcher forKeyPath:@"localizedSummaryItems"];
        }
        Check([TSPDFPrintLabelWithoutColon(@"\u00C9chelle\u00A0:") isEqual:@"\u00C9chelle"] && [TSPDFPrintLabelWithoutColon(@"\u7F29\u653E\uFF1A") isEqual:@"\u7F29\u653E"]
              && [TSPDFPrintLabelWithoutColon(@"Scale:") isEqual:@"Scale"], @"summary names lose the colon and the space before it");

        // The choices of a print stay with its document only, and not as the source's scale.
        {
            NSDocument *first = [NSDocument new], *second = [NSDocument new];
            Check(first.printInfo == NSPrintInfo.sharedPrintInfo, @"a new document starts with the shared print info");
            NSPrintInfo *shared = NSPrintInfo.sharedPrintInfo;
            shared.paperSize = NSMakeSize(595.276, 841.89);
            shared.jobDisposition = NSPrintSaveJob;
            NSDictionary *sharedBefore = [shared.dictionary copy];
            StartInfo = first.printInfo;
            Print(input, [dir stringByAppendingPathComponent:@"first.pdf"], ^(TSPDFPrintAccessory *a) {
                a.autoRotate = NO; a.scaleToFit = NO; a.scalePercent = 43;
            }, &arrows);
            TSPDFPrintKeepChoices(LastOperation, first);
            NSMutableDictionary *sharedAfter = [shared.dictionary mutableCopy];
            [sharedAfter removeObjectForKey:NSPrintJobSavingURL];
            NSMutableDictionary *sharedExpected = [sharedBefore mutableCopy];
            [sharedExpected removeObjectForKey:NSPrintJobSavingURL];
            NSMutableSet *changed = [NSMutableSet set];
            // Saving a job records its path and format in the shared print info (AppKit): not a choice.
            for (id key in @[TSPDFPrintAutoRotateKey, TSPDFPrintScalingModeKey, NSPrintScalingFactor, @"TSPDFPrintScale", NSPrintOrientation])
                if (sharedAfter[key] != sharedExpected[key] && ! [sharedAfter[key] isEqual:sharedExpected[key]]) [changed addObject:key];
            Check(changed.count == 0, [NSString stringWithFormat:@"the shared print info keeps no choice (changed: %@)", [changed.allObjects componentsJoinedByString:@", "]]);
            Check(first.printInfo != shared && [first.printInfo.dictionary[NSPrintScalingFactor] doubleValue] == [sharedBefore[NSPrintScalingFactor] ?: @1 doubleValue],
                  @"the document has its own print info, its scale for the source unchanged");
            __block BOOL rotate = YES, fit = YES; __block NSInteger percent = 0;
            StartInfo = first.printInfo;
            Print(input, [dir stringByAppendingPathComponent:@"first-again.pdf"], ^(TSPDFPrintAccessory *a) { rotate = a.autoRotate; fit = a.scaleToFit; percent = a.scalePercent; }, &arrows);
            Check(! rotate && ! fit && percent == 43, @"the document's next print starts from its choices");
            StartInfo = second.printInfo;
            Print(input, [dir stringByAppendingPathComponent:@"second.pdf"], ^(TSPDFPrintAccessory *a) { rotate = a.autoRotate; fit = a.scaleToFit; percent = a.scalePercent; }, &arrows);
            Check(rotate && fit && percent == 100, @"another document starts with Auto Rotate and Scale to Fit");
            StartInfo = nil;
        }

        // A first page with /Rotate 90 is shown lying: the paper is landscape.
        if (argc > 3) {
            ExpectLandscape = YES;
            frames = Print(@(argv[3]), [dir stringByAppendingPathComponent:@"rotated-first.pdf"], nil, &arrows);
            Check(frames.count == 2, @"both pages of the PDF whose first page is /Rotate 90 print");
            ExpectLandscape = NO;
        }

        printf("%s\n", failures ? "FAIL" : "PASS: PDF printing turns and scales pages as Preview does");
        return failures ? 1 : 0;
    }
}
