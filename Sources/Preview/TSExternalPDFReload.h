// Stable PDF snapshots and page-relative viewport restoration.
#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>
#include <sys/stat.h>

// Cheap content identity: ctime is reported separately because it also changes
// for metadata such as extended attributes set by sync clients or Finder; a new
// ctime alone only prompts a background content comparison. Dataless
// (online-only) files have no signature, so observing them never triggers a download.
static inline NSString *TSExternalPDFStateFromInfo(NSString *path, const struct stat *info, NSString **changeTime)
{
    if (changeTime) *changeTime = nil;
    if (!path || !S_ISREG(info->st_mode) || (info->st_flags & SF_DATALESS)) return nil;
    if (changeTime) *changeTime = [NSString stringWithFormat:@"%lld.%09ld",
                                   (long long)info->st_ctimespec.tv_sec, info->st_ctimespec.tv_nsec];
    return [NSString stringWithFormat:@"%@:%llu:%llu:%lld:%lld:%ld", path,
            (unsigned long long)info->st_dev, (unsigned long long)info->st_ino,
            (long long)info->st_size, (long long)info->st_mtimespec.tv_sec, info->st_mtimespec.tv_nsec];
}

static inline NSString *TSExternalPDFState(NSString *path, NSString **changeTime)
{
    struct stat info;
    if (changeTime) *changeTime = nil;
    if (!path || stat(path.fileSystemRepresentation, &info)) return nil;
    return TSExternalPDFStateFromInfo(path, &info, changeTime);
}

static inline NSString *TSExternalPDFSignature(NSString *path)
{
    return TSExternalPDFState(path, NULL);
}

PDFDocument *TSExternalPDFSnapshot(NSString *path, NSString *signature);
PDFDocument *TSInitialPDFSnapshot(NSString *path, NSString *signature);
void TSRemoveStalePDFSnapshots(NSString *parent);

// The PDF content on display, identified by a SHA-256 digest so that an in-place
// overwrite keeping size and modification time can be told apart from a change
// of metadata alone. Digests stream the file and must be computed off the main
// thread: -prepareDigest and -matchesFileAtPath:... read files.
@interface TSExternalPDFContent : NSObject
- (instancetype)initWithDocument:(PDFDocument *)document path:(NSString *)path
                       signature:(NSString *)signature changeTime:(NSString *)changeTime;
// Digests a file read in place now, while it still matches the recorded state.
// Snapshot clones are immutable and are digested only when first compared.
- (void)prepareDigest;
// YES only if the file still has this state and the same digest as the content.
- (BOOL)matchesFileAtPath:(NSString *)path signature:(NSString *)signature changeTime:(NSString *)changeTime;
@end

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
    // On macOS 26, NSClipView can offset an already valid origin in constrainBoundsRect:.
    // Obtain the scroll limits at the document edges, then clamp without changing
    // an interior position. Keep native inset/centering rules for smaller pages.
    NSRect documentRect = clip.documentRect;
    NSEdgeInsets insets = scroll.contentInsets;
    CGFloat horizontalMargin = target.size.width + fabs(insets.left) + fabs(insets.right) + 1;
    CGFloat verticalMargin = target.size.height + fabs(insets.top) + fabs(insets.bottom) + 1;
    NSRect lower = target, upper = target;
    lower.origin = NSMakePoint(NSMinX(documentRect) - horizontalMargin,
                               NSMinY(documentRect) - verticalMargin);
    upper.origin = NSMakePoint(NSMaxX(documentRect) + horizontalMargin,
                               NSMaxY(documentRect) + verticalMargin);
    lower = [clip constrainBoundsRect:lower];
    upper = [clip constrainBoundsRect:upper];
    target.origin.x = fmin(fmax(target.origin.x, lower.origin.x), upper.origin.x);
    target.origin.y = fmin(fmax(target.origin.y, lower.origin.y), upper.origin.y);
    [clip scrollToPoint:target.origin];
    [scroll reflectScrolledClipView:clip];
}
