// Fit to Content Width (#62). PDFKit draws on the main thread, a few pages at a time.
// An unencrypted document opened from its private clone, with no drawing annotation, is drawn
// by up to four Core Graphics workers instead. The workers never touch PDFKit objects.
#import "TSContentWidth.h"
#import "TSExternalPDFReload.h"
#import <stdatomic.h>

// The preview view implements this. The header is not imported here.
@protocol TSContentWidthMeasuring <NSObject>
- (void)measureContentLater;
@end

const char TSContentWidthStateKey = 0;

// Set while annotations are only being read or a page is being drawn, so PDFKit filling
// them in does not look like an edit.
static BOOL TSContentWidthSuppressNotes = NO;

static void TSContentWidthMarkCGFailed(PDFDocument *document, PDFDisplayBox box)
{
    if (!document) return;
    NSMutableSet *failed = TSContentWidthState(document)[@"cgFailed"];
    [failed addObject:TSContentWidthBoxKey(box, TSContentWidthGeneration(document))];
}

static BOOL TSContentWidthCGFailed(PDFDocument *document, PDFDisplayBox box)
{
    NSMutableSet *failed = TSContentWidthExistingState(document)[@"cgFailed"];
    return [failed containsObject:TSContentWidthBoxKey(box, TSContentWidthGeneration(document))];
}

// The scan shared by both drawings. Row 0 of the bitmap is the top of the page as shown.
static TSContentInkStatus TSContentInkScan(CGContextRef context, CGRect drawn, CGFloat resolution,
                                           CGAffineTransform toPage, NSRect *ink)
{
    const uint8_t *pixels = CGBitmapContextGetData(context);
    size_t width = CGBitmapContextGetWidth(context), height = CGBitmapContextGetHeight(context);
    size_t bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    if (!pixels || width == 0 || height == 0) return TSContentInkFailed;
    NSInteger minX = (NSInteger)width, minY = (NSInteger)height, maxX = -1, maxY = -1;
    for (size_t row = 0; row < height; row++) {
        const uint8_t *line = pixels + row * bytesPerRow;
        for (size_t column = 0; column < width; column++) {
            if (line[column] < 240) {
                minX = MIN(minX, (NSInteger)column);
                maxX = MAX(maxX, (NSInteger)column);
                minY = MIN(minY, (NSInteger)row);
                maxY = MAX(maxY, (NSInteger)row);
            }
        }
    }
    if (maxX < 0) return TSContentInkBlank;
    CGRect found = CGRectMake(CGRectGetMinX(drawn) + minX / resolution,
                              CGRectGetMinY(drawn) + (height - 1 - maxY) / resolution,
                              (maxX - minX + 1) / resolution,
                              (maxY - minY + 1) / resolution);
    CGRect page = CGRectStandardize(CGRectApplyAffineTransform(found, toPage));
    if (!isfinite(page.origin.x) || !isfinite(page.origin.y) || !isfinite(page.size.width) || !isfinite(page.size.height) ||
        page.size.width <= 0 || page.size.height <= 0)
        return TSContentInkFailed;
    if (ink) *ink = NSRectFromCGRect(page);
    return TSContentInkFound;
}

static BOOL TSContentInkSize(CGFloat width, CGFloat height, CGFloat limit, CGFloat *resolution, size_t *pixelsWide, size_t *pixelsHigh)
{
    if (!isfinite(width) || !isfinite(height) || width <= 0 || height <= 0 || !isfinite(limit) || limit <= 0)
        return NO;
    CGFloat scale = MIN(limit, 4000.0 / MAX(width, height));
    if (!isfinite(scale) || scale <= 0) return NO;
    *resolution = scale;
    *pixelsWide = MAX((size_t)1, (size_t)ceil(width * scale));
    *pixelsHigh = MAX((size_t)1, (size_t)ceil(height * scale));
    return YES;
}

static CGContextRef TSContentInkBitmap(size_t width, size_t height)
{
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, gray, (CGBitmapInfo)kCGImageAlphaNone);
    CGColorSpaceRelease(gray);
    if (!context) return NULL;
    CGContextSetGrayFillColor(context, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    return context;
}

TSContentInkStatus TSContentInkMeasure(PDFPage *page, PDFDisplayBox box, CGFloat resolutionLimit, NSRect *ink)
{
    if (ink) *ink = NSZeroRect;
    if (!page) return TSContentInkFailed;
    NSRect bounds = [page boundsForBox:box];
    if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height))
        return TSContentInkFailed;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return TSContentInkFailed;
    CGAffineTransform toDrawn = [page transformForBox:box];
    CGRect drawn = CGRectStandardize(CGRectApplyAffineTransform(NSRectToCGRect(bounds), toDrawn));
    CGFloat resolution = 0;
    size_t width = 0, height = 0;
    if (!TSContentInkSize(CGRectGetWidth(drawn), CGRectGetHeight(drawn), resolutionLimit, &resolution, &width, &height))
        return TSContentInkFailed;
    CGContextRef context = TSContentInkBitmap(width, height);
    if (!context) return TSContentInkFailed;
    CGContextScaleCTM(context, resolution, resolution);
    CGContextTranslateCTM(context, -CGRectGetMinX(drawn), -CGRectGetMinY(drawn));
    // PDFKit can materialize annotations while drawing. That is not an edit.
    BOOL notes = TSContentWidthSuppressNotes;
    TSContentWidthSuppressNotes = YES;
    [page drawWithBox:box toContext:context];
    TSContentWidthSuppressNotes = notes;
    CGAffineTransform back = CGAffineTransformInvert(toDrawn);
    TSContentInkStatus status = TSContentInkScan(context, drawn, resolution, back, ink);
    CGContextRelease(context);
    return status;
}

_Static_assert((int)kPDFDisplayBoxMediaBox == (int)kCGPDFMediaBox, "PDF display boxes match CGPDF boxes");
_Static_assert((int)kPDFDisplayBoxCropBox == (int)kCGPDFCropBox, "PDF display boxes match CGPDF boxes");
_Static_assert((int)kPDFDisplayBoxBleedBox == (int)kCGPDFBleedBox, "PDF display boxes match CGPDF boxes");
_Static_assert((int)kPDFDisplayBoxTrimBox == (int)kCGPDFTrimBox, "PDF display boxes match CGPDF boxes");
_Static_assert((int)kPDFDisplayBoxArtBox == (int)kCGPDFArtBox, "PDF display boxes match CGPDF boxes");

TSContentInkStatus TSContentInkMeasureCG(CGPDFPageRef page, PDFDisplayBox box, CGFloat resolutionLimit, NSRect *ink)
{
    if (ink) *ink = NSZeroRect;
    if (!page) return TSContentInkFailed;
    CGRect bounds = CGPDFPageGetBoxRect(page, (CGPDFBox)box);
    if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height))
        return TSContentInkFailed;
    bounds = CGRectStandardize(bounds);
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return TSContentInkFailed;
    int angle = ((CGPDFPageGetRotationAngle(page) % 360) + 360) % 360;
    BOOL quarter = angle == 90 || angle == 270;
    CGFloat drawnWidth = quarter ? bounds.size.height : bounds.size.width;
    CGFloat drawnHeight = quarter ? bounds.size.width : bounds.size.height;
    CGFloat resolution = 0;
    size_t width = 0, height = 0;
    if (!TSContentInkSize(drawnWidth, drawnHeight, resolutionLimit, &resolution, &width, &height))
        return TSContentInkFailed;
    CGContextRef context = TSContentInkBitmap(width, height);
    if (!context) return TSContentInkFailed;
    CGRect destination = CGRectMake(0, 0, drawnWidth, drawnHeight);
    CGAffineTransform drawing = CGPDFPageGetDrawingTransform(page, (CGPDFBox)box, destination, 0, true);
    CGContextSaveGState(context);
    CGContextScaleCTM(context, resolution, resolution);
    CGContextConcatCTM(context, drawing);
    // drawWithBox: clips to the requested box. Ink outside a CropBox stays out of the fit.
    CGContextClipToRect(context, bounds);
    CGContextDrawPDFPage(context, page);
    CGContextRestoreGState(context);
    CGAffineTransform back = CGAffineTransformInvert(drawing);
    TSContentInkStatus status = TSContentInkScan(context, destination, resolution, back, ink);
    CGContextRelease(context);
    return status;
}

// PDFAnnotation.type is "Link"; the PDFAnnotationSubtype constants are "/Link".
static BOOL TSContentWidthTypeIs(PDFAnnotation *annotation, NSString *subtype)
{
    NSString *type = annotation.type, *name = subtype;
    if ([type hasPrefix:@"/"]) type = [type substringFromIndex:1];
    if ([name hasPrefix:@"/"]) name = [name substringFromIndex:1];
    return type.length && [type isEqualToString:name];
}

static BOOL TSContentWidthAnnotationIgnored(PDFAnnotation *annotation)
{
    // A popup can draw when it opens. It stays on the PDFKit measurement even if it is hidden now.
    if (TSContentWidthTypeIs(annotation, PDFAnnotationSubtypePopup)) return NO;
    if (!annotation.shouldDisplay) return YES;
    if (!TSContentWidthTypeIs(annotation, PDFAnnotationSubtypeLink)) return NO;
    // An appearance stream can draw ink that Core Graphics will not draw for the annotation.
    if (annotation.hasAppearanceStream || annotation.annotationKeyValues[PDFAnnotationKeyAppearanceDictionary]) return NO;
    CGFloat width = annotation.border ? annotation.border.lineWidth : 0;
    id style = annotation.annotationKeyValues[PDFAnnotationKeyBorderStyle];
    if ([style isKindOfClass:[NSDictionary class]]) {
        id line = ((NSDictionary *)style)[@"W"];
        if ([line respondsToSelector:@selector(doubleValue)]) width = MAX(width, [line doubleValue]);
    }
    return width <= 0;
}

static BOOL TSContentWidthFastPathDocument(PDFDocument *document, PDFDisplayBox box)
{
    if (!document || document.isEncrypted || document.isLocked || document.pageCount == 0) return NO;
    if (TSContentWidthDrawingDiverged(document) || TSContentWidthCGFailed(document, box)) return NO;
    return TSExternalPDFCloneURL(document) != nil;
}

// The walk is the slow part on a long PDF. A slice stops before the next page is opened
// and again between annotations. A page with no annotations never reaches the inner check,
// and opening every such page in one turn held the main thread for seconds (#62). One page
// of links can take longer than the slice by itself, so the inner check stays. A direct
// caller that does not slice gets one long walk, and the result is kept for this generation.
static TSContentWidthScan TSContentWidthAdvanceAnnotationScan(PDFDocument *document, NSTimeInterval seconds)
{
    NSMutableDictionary *state = TSContentWidthState(document);
    NSInteger decision = [state[@"noteDecision"] integerValue];
    if (decision == TSContentWidthScanAllow || decision == TSContentWidthScanDeny)
        return (TSContentWidthScan)decision;
    NSUInteger index = [state[@"noteIndex"] unsignedIntegerValue];
    NSUInteger annotationIndex = [state[@"noteAnnot"] unsignedIntegerValue];
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 0)];
    BOOL allow = YES;
    TSContentWidthSuppressNotes = YES;
    @try {
        for (; index < document.pageCount; index++) {
            if (end.timeIntervalSinceNow < 0) {
                state[@"noteIndex"] = @(index);
                state[@"noteAnnot"] = @(annotationIndex);
                return TSContentWidthScanPending;
            }
            PDFPage *page = [document pageAtIndex:index];
            NSArray<PDFAnnotation *> *annotations = page.annotations;
            NSUInteger count = annotations.count;
            for (; annotationIndex < count; annotationIndex++) {
                if (end.timeIntervalSinceNow < 0) {
                    state[@"noteIndex"] = @(index);
                    state[@"noteAnnot"] = @(annotationIndex);
                    return TSContentWidthScanPending;
                }
                if (!TSContentWidthAnnotationIgnored(annotations[annotationIndex])) {
                    allow = NO;
                    break;
                }
            }
            if (!allow) break;
            annotationIndex = 0;
        }
    } @finally {
        TSContentWidthSuppressNotes = NO;
    }
    [state removeObjectForKey:@"noteIndex"];
    [state removeObjectForKey:@"noteAnnot"];
    state[@"noteDecision"] = @(allow ? TSContentWidthScanAllow : TSContentWidthScanDeny);
    return allow ? TSContentWidthScanAllow : TSContentWidthScanDeny;
}

TSContentWidthScan TSContentWidthPrepareFast(PDFDocument *document, PDFDisplayBox box, NSTimeInterval seconds)
{
    if (!TSContentWidthFastPathDocument(document, box)) return TSContentWidthScanDeny;
    return TSContentWidthAdvanceAnnotationScan(document, seconds);
}

static BOOL TSContentWidthAnnotationsAllow(PDFDocument *document)
{
    return TSContentWidthAdvanceAnnotationScan(document, 3600) == TSContentWidthScanAllow;
}

static BOOL TSContentWidthFastPathAllowed(PDFDocument *document, PDFDisplayBox box)
{
    if (!TSContentWidthFastPathDocument(document, box)) return NO;
    return TSContentWidthAnnotationsAllow(document);
}

#pragma mark Jobs

static const NSUInteger TSContentWidthParallelPages = 48;
static const NSInteger TSContentWidthWorkers = 4;

typedef struct {
    int status;
    CGFloat x, y, w, h;
} TSContentWidthSlot;

@interface TSContentWidthJob : NSObject {
@public
    _Atomic int cancelled, failed, ineligible, finished;
    TSContentWidthSlot *slots;
}
@property (strong) PDFDocument *document;
@property PDFDisplayBox box;
@property NSInteger generation;
@property NSUInteger pageCount;
@property (copy) NSURL *url;
@property NSInteger workers;
@property (strong) NSMapTable<PDFView *, id> *callbacks;
@end

@implementation TSContentWidthJob
- (void)dealloc
{
    free(slots);
}
@end

static NSMutableDictionary<NSString *, TSContentWidthJob *> *TSContentWidthJobs;
static NSHashTable<PDFView *> *TSContentWidthViews;
static NSOperationQueue *TSContentWidthQueue;

static NSOperationQueue *TSContentWidthWorkersQueue(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TSContentWidthQueue = [NSOperationQueue new];
        TSContentWidthQueue.maxConcurrentOperationCount = TSContentWidthWorkers;
        TSContentWidthQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        TSContentWidthQueue.name = @"TeXShop content width";
        TSContentWidthJobs = [NSMutableDictionary dictionary];
        TSContentWidthViews = [NSHashTable weakObjectsHashTable];
    });
    return TSContentWidthQueue;
}

static NSString *TSContentWidthJobKey(PDFDocument *document, PDFDisplayBox box, NSInteger generation)
{
    return [NSString stringWithFormat:@"%p:%ld:%ld", document, (long)box, (long)generation];
}

static void TSContentWidthAdvance(PDFDocument *document, BOOL diverged)
{
    if (!document || TSContentWidthSuppressNotes) return;
    NSMutableDictionary *state = TSContentWidthState(document);
    if (diverged) state[@"diverged"] = @YES;
    state[@"generation"] = @([state[@"generation"] integerValue] + 1);
    [state[@"stores"] removeAllObjects];
    [state removeObjectForKey:@"noteIndex"];
    [state removeObjectForKey:@"noteAnnot"];
    [state removeObjectForKey:@"noteDecision"];
    NSMutableArray<NSString *> *scanKeys = [NSMutableArray array];
    for (id key in state)
        if ([key isKindOfClass:[NSString class]] && [(NSString *)key hasPrefix:@"scan:"]) [scanKeys addObject:key];
    [state removeObjectsForKeys:scanKeys];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in TSContentWidthJobs) {
        TSContentWidthJob *job = TSContentWidthJobs[key];
        if (job.document != document) continue;
        atomic_store(&job->cancelled, 1);
        [keys addObject:key];
    }
    [TSContentWidthJobs removeObjectsForKeys:keys];
}

void TSContentWidthNoteAnnotationChange(PDFDocument *document)
{
    // Reading annotations, or drawing a page, can make PDFKit add one. That is not an edit,
    // and it must not start another measurement while a slice still has the main thread.
    if (TSContentWidthSuppressNotes) return;
    TSContentWidthAdvance(document, NO);
    for (PDFView *view in TSContentWidthViews.allObjects) {
        if (view.document == document && [view respondsToSelector:@selector(measureContentLater)])
            [(id<TSContentWidthMeasuring>)view measureContentLater];
    }
}

void TSContentWidthNoteDrawingDiverged(PDFDocument *document)
{
    if (!document) return;
    // A page draw or an annotation walk sets the flag. A structural change during one of
    // those still has to drop the clone. Starting another measurement from inside the walk
    // would re-enter the slice that is already on the main thread.
    BOOL suppressed = TSContentWidthSuppressNotes;
    TSContentWidthSuppressNotes = NO;
    TSContentWidthAdvance(document, YES);
    TSContentWidthSuppressNotes = suppressed;
    if (suppressed) return;
    for (PDFView *view in TSContentWidthViews.allObjects) {
        if (view.document == document && [view respondsToSelector:@selector(measureContentLater)])
            [(id<TSContentWidthMeasuring>)view measureContentLater];
    }
}

void TSContentWidthWatch(PDFView *view)
{
    if (!view) return;
    TSContentWidthWorkersQueue();
    [TSContentWidthViews addObject:view];
}

static char TSContentWidthTokenKey;

NSUInteger TSContentWidthTakeToken(id view)
{
    NSUInteger token = [objc_getAssociatedObject(view, &TSContentWidthTokenKey) unsignedIntegerValue] + 1;
    objc_setAssociatedObject(view, &TSContentWidthTokenKey, @(token), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return token;
}

BOOL TSContentWidthTokenCurrent(id view, NSUInteger token)
{
    return [objc_getAssociatedObject(view, &TSContentWidthTokenKey) unsignedIntegerValue] == token;
}

static BOOL TSContentWidthShown(PDFDocument *document)
{
    for (PDFView *view in TSContentWidthViews.allObjects)
        if (view.document == document) return YES;
    return NO;
}

void TSContentWidthDocumentVisibilityChanged(PDFDocument *document)
{
    if (!document || TSContentWidthShown(document)) return;
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSString *key in TSContentWidthJobs) {
        TSContentWidthJob *job = TSContentWidthJobs[key];
        if (job.document != document) continue;
        atomic_store(&job->cancelled, 1);
        [keys addObject:key];
    }
    [TSContentWidthJobs removeObjectsForKeys:keys];
}

static void TSContentWidthFinish(TSContentWidthJob *job)
{
    if (atomic_fetch_add(&job->finished, 1) + 1 != job.workers) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *key = TSContentWidthJobKey(job.document, job.box, job.generation);
        if (TSContentWidthJobs[key] == job) [TSContentWidthJobs removeObjectForKey:key];
        TSContentWidthResult result = TSContentWidthResultReady;
        BOOL stale = atomic_load(&job->cancelled) || job.generation != TSContentWidthGeneration(job.document) ||
            job.document.pageCount != job.pageCount;
        if (stale)
            result = TSContentWidthResultRetry;
        else if (atomic_load(&job->failed) || atomic_load(&job->ineligible)) {
            TSContentWidthMarkCGFailed(job.document, job.box);
            result = TSContentWidthResultPDFKit;
        } else {
            for (NSUInteger index = 0; index < job.pageCount; index++) {
                TSContentWidthSlot slot = job->slots[index];
                if (slot.status != 1 && slot.status != 2) {
                    TSContentWidthClearBox(job.document, job.box);
                    TSContentWidthMarkCGFailed(job.document, job.box);
                    result = TSContentWidthResultPDFKit;
                    break;
                }
                PDFPage *page = [job.document pageAtIndex:index];
                if (!page) {
                    TSContentWidthClearBox(job.document, job.box);
                    TSContentWidthMarkCGFailed(job.document, job.box);
                    result = TSContentWidthResultPDFKit;
                    break;
                }
                NSRect ink = slot.status == 2 ? NSZeroRect : NSMakeRect(slot.x, slot.y, slot.w, slot.h);
                TSContentWidthStoreRaw(job.document, job.box, page, ink);
            }
        }
        NSMapTable *callbacks = job.callbacks;
        for (PDFView *view in callbacks) {
            void (^done)(TSContentWidthResult) = [callbacks objectForKey:view];
            if (done) done(result);
        }
        free(job->slots);
        job->slots = NULL;
    });
}

static void TSContentWidthRunWorker(TSContentWidthJob *job, NSUInteger start)
{
    CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((__bridge CFURLRef)job.url);
    if (!document || CGPDFDocumentIsEncrypted(document) || CGPDFDocumentGetNumberOfPages(document) != job.pageCount) {
        if (document) CGPDFDocumentRelease(document);
        atomic_store(&job->ineligible, 1);
        TSContentWidthFinish(job);
        return;
    }
    for (NSUInteger index = start; index < job.pageCount; index += (NSUInteger)job.workers) {
        if (atomic_load(&job->cancelled)) break;
        CGPDFPageRef page = CGPDFDocumentGetPage(document, index + 1);
        NSRect ink = NSZeroRect;
        TSContentInkStatus status = page ? TSContentInkMeasureCG(page, job.box, 1.0, &ink) : TSContentInkFailed;
        if (status == TSContentInkFailed) {
            atomic_store(&job->failed, 1);
            break;
        }
        // 0 is an unmeasured slot. Blank must not use it, or a skipped page is stored as blank.
        job->slots[index].status = status == TSContentInkBlank ? 2 : 1;
        job->slots[index].x = ink.origin.x;
        job->slots[index].y = ink.origin.y;
        job->slots[index].w = ink.size.width;
        job->slots[index].h = ink.size.height;
    }
    CGPDFDocumentRelease(document);
    TSContentWidthFinish(job);
}

BOOL TSContentWidthScheduleFast(PDFView *view, void (^done)(TSContentWidthResult result))
{
    PDFDocument *document = view.document;
    PDFDisplayBox box = view.displayBox;
    if (!TSContentWidthFastPathAllowed(document, box)) return NO;
    TSContentWidthWorkersQueue();
    NSInteger generation = TSContentWidthGeneration(document);
    NSString *key = TSContentWidthJobKey(document, box, generation);
    TSContentWidthJob *job = TSContentWidthJobs[key];
    if (!job) {
        NSURL *url = TSExternalPDFCloneURL(document);
        if (!url) return NO;
        job = [TSContentWidthJob new];
        job.document = document;
        job.box = box;
        job.generation = generation;
        job.pageCount = document.pageCount;
        job.url = url;
        job.workers = document.pageCount < TSContentWidthParallelPages ? 1 : TSContentWidthWorkers;
        job.callbacks = [NSMapTable weakToStrongObjectsMapTable];
        job->slots = calloc(job.pageCount, sizeof(TSContentWidthSlot));
        if (!job->slots) return NO;
        TSContentWidthJobs[key] = job;
        // The queue runs workers only. Waiting for them on this queue would take one of the
        // four slots and could stall the workers behind the waiter.
        for (NSUInteger worker = 0; worker < (NSUInteger)job.workers; worker++) {
            [TSContentWidthQueue addOperationWithBlock:^{
                TSContentWidthRunWorker(job, worker);
            }];
        }
    }
    if (done) [job.callbacks setObject:[done copy] forKey:view];
    return YES;
}

BOOL TSContentWidthMeasureSlice(PDFDocument *document, PDFDisplayBox box, NSTimeInterval seconds, BOOL *failed)
{
    if (failed) *failed = NO;
    if (!document || document.isLocked || document.pageCount == 0) return NO;
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:MAX(seconds, 0)];
    NSInteger generation = TSContentWidthGeneration(document);
    // Continue after the stored prefix. Rereading it from page 0 used the whole slice on a
    // long document, and the next slice started there again. A generation change clears the
    // pages already stored, so the remembered index belongs to the old generation.
    for (NSUInteger index = TSContentWidthScanIndex(document, box); index < document.pageCount; index++) {
        if (TSContentWidthGeneration(document) != generation) {
            TSContentWidthClearScanIndex(document, box);
            return NO;
        }
        if (end.timeIntervalSinceNow < 0) {
            TSContentWidthSetScanIndex(document, box, index);
            return NO;
        }
        PDFPage *page = [document pageAtIndex:index];
        // Inserting, deleting or reordering during the draw advances the generation and
        // clears the store. The ink of that draw belongs to the generation that was current
        // when the draw started, so it is not written into the new one, and the new one is
        // not recorded as a failure either (#62).
        if (TSContentWidthGeneration(document) != generation) {
            TSContentWidthClearScanIndex(document, box);
            return NO;
        }
        if (!page) {
            TSContentWidthClearBox(document, box);
            if (failed) *failed = YES;
            return NO;
        }
        BOOL known = NO;
        TSContentWidthRawInk(document, box, page, &known);
        if (known) continue;
        NSRect ink = NSZeroRect;
        TSContentInkStatus status = TSContentInkMeasure(page, box, 1.0, &ink);
        if (TSContentWidthGeneration(document) != generation) {
            TSContentWidthClearScanIndex(document, box);
            return NO;
        }
        if (status == TSContentInkFailed) {
            TSContentWidthClearBox(document, box);
            if (failed) *failed = YES;
            return NO;
        }
        TSContentWidthStoreRaw(document, box, page, status == TSContentInkBlank ? NSZeroRect : ink);
    }
    if (TSContentWidthGeneration(document) != generation) {
        TSContentWidthClearScanIndex(document, box);
        return NO;
    }
    TSContentWidthSetScanIndex(document, box, document.pageCount);
    return TSContentWidthIsComplete(document, box);
}

#pragma mark Annotation edits

static void TSContentWidthSwizzle(Class cls, SEL original, SEL replacement)
{
    Method first = class_getInstanceMethod(cls, original);
    Method second = class_getInstanceMethod(cls, replacement);
    if (first && second) method_exchangeImplementations(first, second);
}

@interface PDFPage (TSContentWidthAnnotations)
- (void)ts_contentWidth_addAnnotation:(PDFAnnotation *)annotation;
- (void)ts_contentWidth_removeAnnotation:(PDFAnnotation *)annotation;
@end

// Inserting, deleting or reordering pages leaves the clone file behind. The fast path
// would store the old page's ink under the new page and mark the document complete.
@interface PDFDocument (TSContentWidthStructure)
- (void)ts_contentWidth_insertPage:(PDFPage *)page atIndex:(NSUInteger)index;
- (void)ts_contentWidth_removePageAtIndex:(NSUInteger)index;
- (void)ts_contentWidth_exchangePageAtIndex:(NSUInteger)index withPageAtIndex:(NSUInteger)other;
@end

@implementation PDFPage (TSContentWidthAnnotations)
+ (void)load
{
    TSContentWidthSwizzle(self, @selector(addAnnotation:), @selector(ts_contentWidth_addAnnotation:));
    TSContentWidthSwizzle(self, @selector(removeAnnotation:), @selector(ts_contentWidth_removeAnnotation:));
}
- (void)ts_contentWidth_addAnnotation:(PDFAnnotation *)annotation
{
    [self ts_contentWidth_addAnnotation:annotation];
    TSContentWidthNoteAnnotationChange(self.document);
}
- (void)ts_contentWidth_removeAnnotation:(PDFAnnotation *)annotation
{
    PDFDocument *document = self.document;
    [self ts_contentWidth_removeAnnotation:annotation];
    TSContentWidthNoteAnnotationChange(document);
}
@end

@implementation PDFDocument (TSContentWidthStructure)
+ (void)load
{
    TSContentWidthSwizzle(self, @selector(insertPage:atIndex:), @selector(ts_contentWidth_insertPage:atIndex:));
    TSContentWidthSwizzle(self, @selector(removePageAtIndex:), @selector(ts_contentWidth_removePageAtIndex:));
    TSContentWidthSwizzle(self, @selector(exchangePageAtIndex:withPageAtIndex:),
                          @selector(ts_contentWidth_exchangePageAtIndex:withPageAtIndex:));
}
- (void)ts_contentWidth_insertPage:(PDFPage *)page atIndex:(NSUInteger)index
{
    [self ts_contentWidth_insertPage:page atIndex:index];
    TSContentWidthNoteDrawingDiverged(self);
}
- (void)ts_contentWidth_removePageAtIndex:(NSUInteger)index
{
    [self ts_contentWidth_removePageAtIndex:index];
    TSContentWidthNoteDrawingDiverged(self);
}
- (void)ts_contentWidth_exchangePageAtIndex:(NSUInteger)index withPageAtIndex:(NSUInteger)other
{
    [self ts_contentWidth_exchangePageAtIndex:index withPageAtIndex:other];
    TSContentWidthNoteDrawingDiverged(self);
}
@end
