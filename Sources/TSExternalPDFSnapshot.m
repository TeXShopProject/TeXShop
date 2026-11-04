// added by Terada: Immutable file-backed snapshots avoid two full PDF data copies.
#import "TSExternalPDFReload.h"
#include <copyfile.h>

@interface TSExternalPDFDocument : PDFDocument
@property (copy) NSString *snapshotDirectory;
@end
@implementation TSExternalPDFDocument
- (void)dealloc
{
    if (_snapshotDirectory)
        [[NSFileManager defaultManager] removeItemAtPath:_snapshotDirectory error:NULL];
}
@end

PDFDocument *TSExternalPDFSnapshot(NSString *path, NSString *signature)
{
    if (!signature || ![signature isEqualToString:TSExternalPDFSignature(path)]) return nil;
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [@"TeXShop-PDF-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![files createDirectoryAtPath:directory withIntermediateDirectories:NO
                          attributes:@{NSFilePosixPermissions:@0700} error:NULL]) return nil;
    NSString *snapshot = [directory stringByAppendingPathComponent:@"snapshot.pdf"];
    // APFS uses copy-on-write; other volumes fall back to a streaming file copy.
    // Keep this private file until PDFKit finishes lazy page/resource loading.
    if (copyfile(path.fileSystemRepresentation, snapshot.fileSystemRepresentation,
                 NULL, COPYFILE_DATA | COPYFILE_CLONE) != 0 ||
        ![signature isEqualToString:TSExternalPDFSignature(path)]) {
        [files removeItemAtPath:directory error:NULL];
        return nil;
    }
    TSExternalPDFDocument *document = [[TSExternalPDFDocument alloc]
                                     initWithURL:[NSURL fileURLWithPath:snapshot]];
    if (!document) { [files removeItemAtPath:directory error:NULL]; return nil; }
    document.snapshotDirectory = directory;
    if (!document.pageCount || document.isLocked) return nil;
    return document;
}
