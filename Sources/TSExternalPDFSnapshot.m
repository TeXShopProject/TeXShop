// Immutable file-backed snapshots avoid two full PDF data copies.
#import "TSExternalPDFReload.h"
#include <copyfile.h>
#include <stdlib.h>

// Track only this process's private directories, including documents retained at exit.
static NSMutableSet<NSString *> *TSSnapshotDirectories;
static void TSCleanupPDFSnapshots(void)
{
    @autoreleasepool {
        @synchronized (TSSnapshotDirectories) {
            for (NSString *path in TSSnapshotDirectories)
                [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        }
    }
}
static void TSRemovePDFSnapshot(NSString *path)
{
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    @synchronized (TSSnapshotDirectories) { [TSSnapshotDirectories removeObject:path]; }
}

@interface TSExternalPDFDocument : PDFDocument
@property (copy) NSString *snapshotDirectory;
@end
@implementation TSExternalPDFDocument
- (void)dealloc
{
    if (_snapshotDirectory)
        TSRemovePDFSnapshot(_snapshotDirectory);
}
@end

static PDFDocument *TSPDFSnapshot(NSString *path, NSString *signature, BOOL allowLocked)
{
    if (!signature || ![signature isEqualToString:TSExternalPDFSignature(path)]) return nil;
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [@"TeXShop-PDF-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:NO
                          attributes:@{NSFilePosixPermissions:@0700} error:NULL]) return nil;
    // COPYFILE_CLONE copies symlinks themselves. Resolve the source first while
    // validating the caller's original path before and after the copy.
    NSString *resolvedPath = path.stringByResolvingSymlinksInPath;
    NSString *resolvedSignature = TSExternalPDFSignature(resolvedPath);
    NSString *expectedResolvedSignature = [resolvedPath stringByAppendingString:[signature substringFromIndex:path.length]];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TSSnapshotDirectories = [NSMutableSet new];
        atexit(TSCleanupPDFSnapshots);
    });
    @synchronized (TSSnapshotDirectories) { [TSSnapshotDirectories addObject:directory]; }
    NSString *snapshot = [directory stringByAppendingPathComponent:@"snapshot.pdf"];
    // APFS uses copy-on-write; other volumes fall back to a streaming file copy.
    // Keep this private file until PDFKit finishes lazy page/resource loading.
    if (![resolvedSignature isEqualToString:expectedResolvedSignature] || copyfile(resolvedPath.fileSystemRepresentation, snapshot.fileSystemRepresentation,
                 NULL, COPYFILE_DATA | COPYFILE_CLONE) != 0 ||
        ![signature isEqualToString:TSExternalPDFSignature(path)] ||
        ![resolvedSignature isEqualToString:TSExternalPDFSignature(resolvedPath)]) {
        TSRemovePDFSnapshot(directory);
        return nil;
    }
    TSExternalPDFDocument *document = [[TSExternalPDFDocument alloc]
                                     initWithURL:[NSURL fileURLWithPath:snapshot]];
    if (!document) { TSRemovePDFSnapshot(directory); return nil; }
    document.snapshotDirectory = directory;
    if (document.isLocked ? !allowLocked : !document.pageCount) return nil;
    return document;
}

PDFDocument *TSExternalPDFSnapshot(NSString *path, NSString *signature)
{
    return TSPDFSnapshot(path, signature, NO);
}

// Initial/explicit loads must let PDFKit show its password entry field.
PDFDocument *TSInitialPDFSnapshot(NSString *path, NSString *signature)
{
    return TSPDFSnapshot(path, signature, YES);
}
