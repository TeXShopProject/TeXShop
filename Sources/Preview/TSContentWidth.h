#pragma once
// Fit to Content Width (#62). The resolution-1.0 ink of every page, kept apart from the
// resolution-2.0 store that Zoom to Content uses. A rect in the store is raw ink, with no
// margin. An empty rect with a key is a blank page. A missing key is a page not measured yet.
#import <Quartz/Quartz.h>
#import <objc/runtime.h>
#import <math.h>

typedef NS_ENUM(NSInteger, TSContentInkStatus) {
    TSContentInkBlank = 0,
    TSContentInkFound = 1,
    TSContentInkFailed = 2,
};

// What a finished measurement tells the view that asked for it.
typedef NS_ENUM(NSInteger, TSContentWidthResult) {
    TSContentWidthResultReady = 0,  // the resolution-1.0 store is complete
    TSContentWidthResultPDFKit = 1, // measure on the main thread instead
    TSContentWidthResultRetry = 2,  // the job was dropped; ask again
};

// PDFKit measurement at resolutionLimit pixels per page unit. The rect is raw ink in page
// coordinates. Blank and failure are different: a blank page has no ink, a failure was not drawn.
TSContentInkStatus TSContentInkMeasure(PDFPage *page, PDFDisplayBox box, CGFloat resolutionLimit, NSRect *ink);

// The same measurement through Core Graphics. The page's /Rotate is applied once, by
// CGPDFPageGetDrawingTransform. page is the caller's, and is not retained.
TSContentInkStatus TSContentInkMeasureCG(CGPDFPageRef page, PDFDisplayBox box, CGFloat resolutionLimit, NSRect *ink);

// The store lives with the document. Jobs and views on the main thread are its only callers.
// One symbol, so a test and TSContentWidth.m share the store.
extern const char TSContentWidthStateKey;

static inline NSMutableDictionary *TSContentWidthExistingState(PDFDocument *document)
{
    if (!document) return nil;
    return objc_getAssociatedObject(document, &TSContentWidthStateKey); // key is the extern symbol
}

static inline NSMutableDictionary *TSContentWidthState(PDFDocument *document)
{
    NSMutableDictionary *state = TSContentWidthExistingState(document);
    if (document && !state) {
        state = [NSMutableDictionary dictionary];
        state[@"generation"] = @0;
        state[@"diverged"] = @NO;
        state[@"stores"] = [NSMutableDictionary dictionary];
        state[@"failures"] = [NSMutableSet set];
        state[@"cgFailed"] = [NSMutableSet set];
        objc_setAssociatedObject(document, &TSContentWidthStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static inline NSMapTable<PDFPage *, NSValue *> *TSContentWidthStore(PDFDocument *document, PDFDisplayBox box, BOOL create)
{
    NSMutableDictionary *stores = (create ? TSContentWidthState(document) : TSContentWidthExistingState(document))[@"stores"];
    if (!stores) return nil;
    NSMapTable *store = stores[@(box)];
    if (!store && create) {
        store = [NSMapTable weakToStrongObjectsMapTable];
        stores[@(box)] = store;
    }
    return store;
}

static inline NSString *TSContentWidthBoxKey(PDFDisplayBox box, NSInteger generation)
{
    return [NSString stringWithFormat:@"%ld:%ld", (long)box, (long)generation];
}

static inline NSInteger TSContentWidthGeneration(PDFDocument *document)
{
    return [TSContentWidthExistingState(document)[@"generation"] integerValue];
}

static inline BOOL TSContentWidthDrawingDiverged(PDFDocument *document)
{
    return [TSContentWidthExistingState(document)[@"diverged"] boolValue];
}

// YES when every page of this display box has a raw-ink rect. A locked document, and a document
// with no pages, is not complete: an empty page count is not a finished blank document.
static inline BOOL TSContentWidthIsComplete(PDFDocument *document, PDFDisplayBox box)
{
    if (!document || document.isLocked || document.pageCount == 0) return NO;
    NSMapTable *store = TSContentWidthStore(document, box, NO);
    if (!store) return NO;
    for (NSUInteger index = 0; index < document.pageCount; index++) {
        PDFPage *page = [document pageAtIndex:index];
        if (!page || ![store objectForKey:page]) return NO;
    }
    return YES;
}

static inline BOOL TSContentWidthHasFailure(PDFDocument *document, PDFDisplayBox box)
{
    NSMutableSet *failures = TSContentWidthExistingState(document)[@"failures"];
    return [failures containsObject:TSContentWidthBoxKey(box, TSContentWidthGeneration(document))];
}

// Raw ink already stored. *known is YES when the page has been measured, including a blank page.
static inline NSRect TSContentWidthRawInk(PDFDocument *document, PDFDisplayBox box, PDFPage *page, BOOL *known)
{
    if (known) *known = NO;
    NSValue *value = page ? [TSContentWidthStore(document, box, NO) objectForKey:page] : nil;
    if (!value) return NSZeroRect;
    if (known) *known = YES;
    return value.rectValue;
}

static inline void TSContentWidthStoreRaw(PDFDocument *document, PDFDisplayBox box, PDFPage *page, NSRect ink)
{
    if (!document || !page) return;
    [TSContentWidthStore(document, box, YES) setObject:[NSValue valueWithRect:ink] forKey:page];
}

static inline void TSContentWidthClearBox(PDFDocument *document, PDFDisplayBox box)
{
    [TSContentWidthStore(document, box, NO) removeAllObjects];
}

static inline void TSContentWidthRecordFailure(PDFDocument *document, PDFDisplayBox box)
{
    if (!document) return;
    [TSContentWidthState(document)[@"failures"] addObject:TSContentWidthBoxKey(box, TSContentWidthGeneration(document))];
    TSContentWidthClearBox(document, box);
}

// The view shows this document, so a measurement of it stays alive while any such view does.
void TSContentWidthWatch(PDFView *view);
// Invalidates a measurement callback already queued for this view. Each measurement takes a token.
NSUInteger TSContentWidthTakeToken(id view);
BOOL TSContentWidthTokenCurrent(id view, NSUInteger token);
// Cancel a measurement whose document is no longer shown.
void TSContentWidthDocumentVisibilityChanged(PDFDocument *document);

// An annotation was added, removed or changed. The generation advances either way, so a job
// that read the old page cannot write its rects back. Link-only edits advance it too.
void TSContentWidthNoteAnnotationChange(PDFDocument *document);
// The displayed document no longer matches the clone it was opened from. It stays on the
// PDFKit measurement for the rest of its life.
void TSContentWidthNoteDrawingDiverged(PDFDocument *document);

// Measures pages that are not stored yet, until the time is up. YES when every page is stored.
// *failed is YES only when a page could not be drawn; the store for the box is then empty.
BOOL TSContentWidthMeasureSlice(PDFDocument *document, PDFDisplayBox box, NSTimeInterval seconds, BOOL *failed);

// Whether the annotation walk may still use the background measurement.
typedef NS_ENUM(NSInteger, TSContentWidthScan) {
    TSContentWidthScanPending = 0, // call again; the walk used the time it was given
    TSContentWidthScanAllow = 1,
    TSContentWidthScanDeny = 2,    // use PDFKit, including a document that cannot use the background
};

// Walks annotations for at most `seconds` when this document can be measured off the main
// thread. An encrypted document, a locked one, and one that was not opened from its clone
// are Deny without a walk. The decision stays with this measurement generation.
TSContentWidthScan TSContentWidthPrepareFast(PDFDocument *document, PDFDisplayBox box, NSTimeInterval seconds);

// Starts a background measurement when this document may use one. NO means the caller measures
// with PDFKit. done runs on the main thread. A decision from TSContentWidthPrepareFast is reused.
BOOL TSContentWidthScheduleFast(PDFView *view, void (^done)(TSContentWidthResult result));
