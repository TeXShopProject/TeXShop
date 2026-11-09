// Immutable file-backed snapshots avoid two full PDF data copies.
#import "TSExternalPDFReload.h"
#include <CommonCrypto/CommonDigest.h>
#include <copyfile.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/resource.h>
#include <stdlib.h>
#include <unistd.h>

static NSString * const TSSnapshotPrefix = @"TeXShop-PDF-";
static NSString * const TSSnapshotName = @"snapshot.pdf";

// Track only this process's private directories, including documents retained at exit.
static NSMutableSet<NSString *> *TSSnapshotDirectories;
// Snapshot parent directory per volume; NSNull marks volumes read in place.
static NSMutableDictionary<NSNumber *, id> *TSSnapshotParents;
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

// Directories are named TeXShop-PDF-<pid>-<UUID>; atexit does not run after a crash.
void TSRemoveStalePDFSnapshots(NSString *parent)
{
    NSFileManager *files = [NSFileManager defaultManager];
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    for (NSString *name in [files contentsOfDirectoryAtPath:parent error:NULL]) {
        if (![name hasPrefix:TSSnapshotPrefix]) continue;
        NSString *owner = [name substringFromIndex:TSSnapshotPrefix.length];
        NSRange separator = [owner rangeOfString:@"-"];
        if (separator.location == NSNotFound || separator.location == 0 || separator.location > 9) continue;
        NSString *pidString = [owner substringToIndex:separator.location];
        if ([pidString rangeOfCharacterFromSet:nonDigits].location != NSNotFound ||
            ![[NSUUID alloc] initWithUUIDString:[owner substringFromIndex:NSMaxRange(separator)]]) continue;
        pid_t pid = (pid_t)pidString.intValue;
        if (pid <= 0 || pid == getpid() || kill(pid, 0) == 0 || errno == EPERM) continue;
        NSString *path = [parent stringByAppendingPathComponent:name];
        struct stat info;
        if (lstat(path.fileSystemRepresentation, &info) || !S_ISDIR(info.st_mode) || info.st_uid != getuid()) continue;
        [files removeItemAtPath:path error:NULL];
    }
}

static BOOL TSSameDirectory(NSString *first, NSString *second)
{
    struct stat a, b;
    return !stat(first.fileSystemRepresentation, &a) && !stat(second.fileSystemRepresentation, &b) &&
        a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

// Clones are possible only within one volume. Resolve a private temporary
// directory on the PDF's own volume once, without holding the lock during I/O.
static NSString *TSSnapshotParent(NSString *path, dev_t device)
{
    id parent;
    @synchronized (TSSnapshotParents) { parent = TSSnapshotParents[@(device)]; }
    if (parent) return parent == NSNull.null ? nil : parent;
    parent = NSNull.null;
    NSFileManager *files = [NSFileManager defaultManager];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSNumber *clones = nil;
    struct stat info;
    if ([url getResourceValue:&clones forKey:NSURLVolumeSupportsFileCloningKey error:NULL] && clones.boolValue) {
        NSString *candidate = NSTemporaryDirectory();
        if (stat(candidate.fileSystemRepresentation, &info) || info.st_dev != device) {
            NSURL *replacement = [files URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask
                                      appropriateForURL:url create:YES error:NULL];
            candidate = replacement.URLByDeletingLastPathComponent.path;
            if (replacement) [files removeItemAtURL:replacement error:NULL];
            // Never place private files beside the user's own documents.
            if (!candidate || stat(candidate.fileSystemRepresentation, &info) || info.st_dev != device ||
                TSSameDirectory(candidate, path.stringByDeletingLastPathComponent)) candidate = nil;
        }
        if (candidate) {
            TSRemoveStalePDFSnapshots(candidate);
            parent = candidate;
        }
    }
    @synchronized (TSSnapshotParents) { TSSnapshotParents[@(device)] = parent; }
    return parent == NSNull.null ? nil : parent;
}

static NSString *TSCreateSnapshotDirectory(NSString *path, dev_t device)
{
    NSString *parent = TSSnapshotParent(path, device);
    if (!parent) return nil;
    NSString *directory = [parent stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%d-%@",
                           TSSnapshotPrefix, getpid(), NSUUID.UUID.UUIDString]];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:NO
                                                   attributes:@{NSFilePosixPermissions:@0700} error:NULL]) {
        // The volume may have been replaced; resolve its directory again next time.
        @synchronized (TSSnapshotParents) { [TSSnapshotParents removeObjectForKey:@(device)]; }
        return nil;
    }
    @synchronized (TSSnapshotDirectories) { [TSSnapshotDirectories addObject:directory]; }
    return directory;
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
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TSSnapshotDirectories = [NSMutableSet new];
        TSSnapshotParents = [NSMutableDictionary new];
        atexit(TSCleanupPDFSnapshots);
    });
    // COPYFILE_CLONE_FORCE clones symlinks themselves. Resolve the source first while
    // validating the caller's original path before and after the clone.
    NSString *resolvedPath = path.stringByResolvingSymlinksInPath;
    NSString *resolvedSignature = TSExternalPDFSignature(resolvedPath);
    NSString *expectedResolvedSignature = [resolvedPath stringByAppendingString:[signature substringFromIndex:path.length]];
    struct stat info;
    if (![resolvedSignature isEqualToString:expectedResolvedSignature] ||
        stat(resolvedPath.fileSystemRepresentation, &info)) return nil;
    PDFDocument *document = nil;
    // Keep this private clone until PDFKit finishes lazy page/resource loading.
    // Never fall back to a full data copy, which can be slow or fill the volume.
    NSString *directory = TSCreateSnapshotDirectory(resolvedPath, info.st_dev);
    if (directory) {
        NSString *snapshot = [directory stringByAppendingPathComponent:TSSnapshotName];
        BOOL cloned = copyfile(resolvedPath.fileSystemRepresentation, snapshot.fileSystemRepresentation,
                               NULL, COPYFILE_CLONE_FORCE) == 0;
        if (cloned) {
            TSExternalPDFDocument *clone = [[TSExternalPDFDocument alloc] initWithURL:[NSURL fileURLWithPath:snapshot]];
            clone.snapshotDirectory = directory;
            document = clone;
        }
        if (!document) TSRemovePDFSnapshot(directory);
        if (cloned && !document) return nil;
    }
    // Without a clone, read the PDF in place as when automatic reloads are off.
    if (!document) document = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:path]];
    if (!document || ![signature isEqualToString:TSExternalPDFSignature(path)] ||
        ![resolvedSignature isEqualToString:TSExternalPDFSignature(resolvedPath)]) return nil;
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

// Streams a regular file through SHA-256; dataless files are never downloaded.
// With a signature, the digest is returned only if the open file had that state,
// including its change time, both before and after it was read.
static NSData *TSPDFDigest(NSString *path, NSString *signature, NSString *changeTime)
{
    int policy = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD);
    setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                   IOPOL_MATERIALIZE_DATALESS_FILES_OFF);
    NSData *digest = nil;
    int file = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    struct stat info;
    NSString *time = nil;
    if (file >= 0 && !fstat(file, &info) && S_ISREG(info.st_mode) && !(info.st_flags & SF_DATALESS) &&
        (!signature || ([signature isEqualToString:TSExternalPDFStateFromInfo(path, &info, &time)] &&
                        [changeTime isEqualToString:time]))) {
        CC_SHA256_CTX context;
        CC_SHA256_Init(&context);
        const size_t length = 1 << 20;
        uint8_t *buffer = malloc(length);
        BOOL complete = NO;
        while (buffer) {
            ssize_t count = read(file, buffer, length);
            if (count > 0) CC_SHA256_Update(&context, buffer, (CC_LONG)count);
            else if (count == 0) { complete = YES; break; }
            else if (errno != EINTR) break;
        }
        free(buffer);
        unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256_Final(bytes, &context);
        if (complete && (!signature || (!fstat(file, &info) &&
                                        [signature isEqualToString:TSExternalPDFStateFromInfo(path, &info, &time)] &&
                                        [changeTime isEqualToString:time])))
            digest = [NSData dataWithBytes:bytes length:sizeof bytes];
    }
    if (file >= 0) close(file);
    if (policy >= 0) setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, policy);
    return digest;
}

@implementation TSExternalPDFContent {
    NSString *_path, *_signature, *_changeTime, *_snapshotFile;
    NSData *_digest;
    BOOL _digested;
}

- (instancetype)initWithDocument:(PDFDocument *)document path:(NSString *)path
                       signature:(NSString *)signature changeTime:(NSString *)changeTime
{
    if ((self = [super init])) {
        _path = [path copy];
        _signature = [signature copy];
        _changeTime = [changeTime copy];
        // Only the path is kept, so the document is never released off the main thread.
        NSString *directory = [document isKindOfClass:TSExternalPDFDocument.class] ?
            ((TSExternalPDFDocument *)document).snapshotDirectory : nil;
        _snapshotFile = [directory stringByAppendingPathComponent:TSSnapshotName];
    }
    return self;
}

// A file read in place is digested only while it still has the recorded state;
// otherwise the digest stays unknown and any later change time counts as a change.
- (NSData *)digest
{
    @synchronized (self) {
        if (!_digested) {
            _digested = YES;
            _digest = _snapshotFile ? TSPDFDigest(_snapshotFile, nil, nil) : TSPDFDigest(_path, _signature, _changeTime);
        }
        return _digest;
    }
}

- (void)prepareDigest
{
    if (!_snapshotFile) [self digest];
}

- (BOOL)matchesFileAtPath:(NSString *)path signature:(NSString *)signature changeTime:(NSString *)changeTime
{
    NSData *digest = [self digest];
    return digest && signature && changeTime && [digest isEqualToData:TSPDFDigest(path, signature, changeTime)];
}
@end
