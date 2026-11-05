// Stable PDF snapshots and page-relative viewport restoration.
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#include <sys/stat.h>

// Content identity only: ctime also changes for metadata such as extended
// attributes set by sync clients or Finder. Dataless (online-only) files have
// no signature, so observing them never triggers a download.
static inline NSString *TSExternalPDFSignature(NSString *path)
{
    struct stat info;
    if (!path || stat(path.fileSystemRepresentation, &info) || !S_ISREG(info.st_mode) ||
        (info.st_flags & SF_DATALESS)) return nil;
    return [NSString stringWithFormat:@"%@:%llu:%llu:%lld:%lld:%ld", path,
            (unsigned long long)info.st_dev, (unsigned long long)info.st_ino,
            (long long)info.st_size, (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
}

PDFDocument *TSExternalPDFSnapshot(NSString *path, NSString *signature);
PDFDocument *TSInitialPDFSnapshot(NSString *path, NSString *signature);
void TSRemoveStalePDFSnapshots(NSString *parent);

typedef struct {
    BOOL valid, autoScales;
    NSUInteger pageIndex;
    NSPoint pagePoint;
    CGFloat scale;
} TSExternalPDFPosition;

static inline TSExternalPDFPosition TSExternalPDFCapture(PDFView *view)
{
    TSExternalPDFPosition position = {0};
    NSClipView *clip = view.documentView.enclosingScrollView.contentView;
    if (!view.document.pageCount || !clip || NSIsEmptyRect(clip.bounds)) return position;
    NSPoint center = [view convertPoint:NSMakePoint(NSMidX(clip.bounds), NSMidY(clip.bounds)) fromView:clip];
    PDFPage *page = [view pageForPoint:center nearest:YES];
    if (!page) return position;
    position.valid = YES;
    position.pageIndex = [view.document indexForPage:page];
    position.pagePoint = [view convertPoint:center toPage:page];
    position.scale = view.scaleFactor;
    position.autoScales = view.autoScales;
    return position;
}

static inline void TSExternalPDFRestore(PDFView *view, TSExternalPDFPosition position)
{
    if (!position.valid || !view.document.pageCount) return;
    if (view.autoScales != position.autoScales) view.autoScales = position.autoScales;
    if (!position.autoScales) view.scaleFactor = position.scale;
    PDFPage *page = [view.document pageAtIndex:MIN(position.pageIndex, view.document.pageCount-1)];
    [view goToPage:page];
    [view layoutDocumentView];
    [view layoutSubtreeIfNeeded];
    NSView *documentView = view.documentView;
    NSScrollView *scroll = documentView.enclosingScrollView;
    NSClipView *clip = scroll.contentView;
    NSPoint point = [documentView convertPoint:[view convertPoint:position.pagePoint fromPage:page] fromView:view];
    NSRect target = clip.bounds;
    target.origin = NSMakePoint(point.x-target.size.width/2, point.y-target.size.height/2);
    target = [clip constrainBoundsRect:target];
    [clip scrollToPoint:target.origin];
    [scroll reflectScrolledClipView:clip];
}
