// added by Terada
#import "TSFileChangeMonitor.h"
#import <sys/event.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

#import <CommonCrypto/CommonDigest.h>

NSData *TSSourceFingerprint(NSData *data)
{
    if (!data) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    const unsigned char *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining) {
        CC_LONG count = (CC_LONG)MIN(remaining, (NSUInteger)UINT32_MAX);
        CC_SHA256_Update(&context, bytes, count);
        bytes += count;
        remaining -= count;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}

static NSString *TSFileStamp(NSString *path)
{
    struct stat s;
    if (stat(path.fileSystemRepresentation, &s) != 0) return nil;
    return [NSString stringWithFormat:@"%llu/%llu/%lld/%lld:%ld/%lld:%ld",
            (unsigned long long)s.st_dev, (unsigned long long)s.st_ino,
            (long long)s.st_size, (long long)s.st_mtimespec.tv_sec, s.st_mtimespec.tv_nsec,
            (long long)s.st_ctimespec.tv_sec, s.st_ctimespec.tv_nsec];
}

@class TSFileWatchWorker;
@interface TSFileChangeMonitor ()
- (void)prepareWorker:(TSFileWatchWorker *)worker;
- (BOOL)acceptData:(NSData *)data fingerprint:(NSData *)fingerprint generation:(NSNumber *)generation;
@end

@interface TSFileWatchWorker : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, weak) TSFileChangeMonitor *owner;
@property (nonatomic, strong) dispatch_queue_t queue;
- (void)start;
- (void)stop;
- (void)readGeneration:(NSNumber *)generation;
@end

@implementation TSFileChangeMonitor {
    TSFileWatchWorker *_worker;
    NSNumber *(^_prepare)(void);
    BOOL (^_accept)(NSData *, NSData *, NSNumber *);
    BOOL _stopped;
}
- (instancetype)initWithPath:(NSString *)path prepare:(NSNumber *(^)(void))prepare
                     accept:(BOOL (^)(NSData *, NSData *, NSNumber *))accept
{
    NSAssert(NSThread.isMainThread, @"Start monitoring on the main thread");
    if (!(self = [super init])) return nil;
    _path = [path.stringByStandardizingPath copy];
    _prepare = [prepare copy]; _accept = [accept copy];
    TSFileWatchWorker *worker = [TSFileWatchWorker new];
    worker.path = _path; worker.owner = self;
    worker.queue = dispatch_queue_create("org.texshop.source-watch", DISPATCH_QUEUE_SERIAL);
    _worker = worker;
    dispatch_async(worker.queue, ^{ [worker start]; });
    return self;
}
- (void)prepareWorker:(TSFileWatchWorker *)worker
{
    NSNumber *generation = !_stopped && _prepare ? _prepare() : nil;
    dispatch_async(worker.queue, ^{ [worker readGeneration:generation]; });
}
- (BOOL)acceptData:(NSData *)data fingerprint:(NSData *)fingerprint generation:(NSNumber *)generation
{
    return !_stopped && _accept ? _accept(data, fingerprint, generation) : NO;
}
- (void)stop
{
    if (_stopped) return;
    _stopped = YES; _prepare = nil; _accept = nil;
    TSFileWatchWorker *worker = _worker; _worker = nil;
    if (worker) dispatch_async(worker.queue, ^{ [worker stop]; });
}
- (void)dealloc { [self stop]; }
@end

@implementation TSFileWatchWorker {
    int _queueFD, _fileFD, _directoryFD;
    dispatch_source_t _events, _poll, _debounce;
    BOOL _stopped, _pending, _inFlight;
    NSUInteger _changeGeneration, _readingGeneration;
    NSTimeInterval _retryAfter, _retryDelay;
    NSString *_stamp;
}
- (instancetype)init
{
    if ((self = [super init])) _queueFD = _fileFD = _directoryFD = -1;
    return self;
}
- (void)start
{
    _queueFD = kqueue();
    if (_queueFD >= 0) {
        fcntl(_queueFD, F_SETFD, FD_CLOEXEC);
        [self attachPath:_path.stringByDeletingLastPathComponent descriptor:&_directoryFD];
        [self attachPath:_path descriptor:&_fileFD];
    }
    _stamp = TSFileStamp(_path);
    __weak TSFileWatchWorker *weakSelf = self;
    if (_queueFD >= 0) {
        _events = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _queueFD, 0, _queue);
        dispatch_source_set_event_handler(_events, ^{ [weakSelf consumeEvents]; });
        int fd = _queueFD;
        dispatch_source_set_cancel_handler(_events, ^{ close(fd); });
        dispatch_resume(_events);
    }
    _debounce = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_debounce, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(_debounce, ^{ [weakSelf attemptReload]; });
    dispatch_resume(_debounce);
    _poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_poll, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                             2 * NSEC_PER_SEC, NSEC_PER_SEC / 5);
    dispatch_source_set_event_handler(_poll, ^{
        TSFileWatchWorker *worker = weakSelf;
        if (!worker || worker->_stopped) return;
        if ([worker refresh]) [worker markChanged];
        else if (worker->_pending) [worker attemptReload];
    });
    dispatch_resume(_poll);
    // Registration is asynchronous. Always compare once against the bytes the
    // document accepted, covering changes before the filters were installed.
    [self markChanged];
}

- (void)attachPath:(NSString *)path descriptor:(int *)descriptor
{
    if (_queueFD < 0) return;
    struct stat current, watched;
    if (stat(path.fileSystemRepresentation, &current) != 0) return;
    if (*descriptor >= 0 && fstat(*descriptor, &watched) == 0 &&
        current.st_dev == watched.st_dev && current.st_ino == watched.st_ino) return;
    int fd = open(path.fileSystemRepresentation, O_EVTONLY | O_CLOEXEC);
    if (fd < 0) return;
    struct kevent change;
    EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR,
           NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB | NOTE_RENAME | NOTE_DELETE | NOTE_REVOKE, 0, NULL);
    if (kevent(_queueFD, &change, 1, NULL, 0, NULL) < 0) {
        close(fd);
        return;
    }
    // Register the replacement before closing the previous descriptor. The
    // parent filter remains installed throughout an atomic file replacement.
    if (*descriptor >= 0) close(*descriptor);
    *descriptor = fd;
}

- (BOOL)refresh
{
    [self attachPath:_path.stringByDeletingLastPathComponent descriptor:&_directoryFD];
    [self attachPath:_path descriptor:&_fileFD];
    NSString *stamp = TSFileStamp(_path);
    BOOL changed = !(_stamp == stamp || [_stamp isEqualToString:stamp]);
    _stamp = stamp;
    return changed;
}

- (void)consumeEvents
{
    if (_stopped) return;
    struct kevent events[16];
    struct timespec immediate = {0, 0};
    int count;
    BOOL fileChanged = NO;
    // Bound each drain so a continuously active writer cannot monopolize the UI.
    for (int batch = 0; batch < 8 &&
         _queueFD >= 0 &&
         (count = kevent(_queueFD, NULL, 0, events, 16, &immediate)) > 0; ++batch) {
        for (int i = 0; i < count; ++i) {
            if (events[i].ident == (uintptr_t)_fileFD) fileChanged = YES;
        }
    }
    BOOL metadataChanged = [self refresh];
    // A write notification matters even when size and modification time match.
    // Conversely, unrelated writes to siblings must not reload this document.
    if (fileChanged || metadataChanged) [self markChanged];
}

- (void)markChanged
{
    _pending = YES; ++_changeGeneration;
    _retryAfter = 0; _retryDelay = 0;
    dispatch_source_set_timer(_debounce, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10),
                             DISPATCH_TIME_FOREVER, NSEC_PER_MSEC * 10);
}

- (void)attemptReload
{
    if (_stopped || !_pending || _inFlight) return;
    if ([self refresh]) { [self markChanged]; return; }
    if (!_stamp || [NSDate timeIntervalSinceReferenceDate] < _retryAfter) return;
    _inFlight = YES; _readingGeneration = _changeGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        TSFileChangeMonitor *owner = self.owner;
        if (owner) [owner prepareWorker:self];
        else dispatch_async(self.queue, ^{ [self stop]; });
    });
}
- (void)readGeneration:(NSNumber *)generation
{
    if (_stopped) return;
    if (!generation) { _inFlight = NO; return; }
    @autoreleasepool {
        NSData *data = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:_path] options:0 error:NULL];
        NSData *fingerprint = TSSourceFingerprint(data);
        if (!data) {
            _inFlight = NO;
            _retryDelay = MIN(30, MAX(2, _retryDelay * 2));
            _retryAfter = [NSDate timeIntervalSinceReferenceDate] + _retryDelay;
            return;
        }
        _retryDelay = 0; _retryAfter = 0;
        NSUInteger readingGeneration = _readingGeneration;
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL accepted = [self.owner acceptData:data fingerprint:fingerprint generation:generation];
            dispatch_async(self.queue, ^{
                if (self->_stopped) return;
                self->_inFlight = NO;
                if (accepted && readingGeneration == self->_changeGeneration) self->_pending = NO;
                // Queued vnode writes are consumed even when metadata was restored.
                [self consumeEvents];
                // A debounce may have fired while this read was in flight.
                // Re-arm only for a newer change, not for a rejected/dirty read.
                if (self->_pending && readingGeneration != self->_changeGeneration)
                    dispatch_source_set_timer(self->_debounce,
                        dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10),
                        DISPATCH_TIME_FOREVER, NSEC_PER_MSEC * 10);
            });
        });
    }
}
- (void)stop
{
    if (_stopped) return;
    _stopped = YES;
    if (_poll) dispatch_source_cancel(_poll);
    if (_debounce) dispatch_source_cancel(_debounce);
    if (_events) dispatch_source_cancel(_events);
    else if (_queueFD >= 0) close(_queueFD);
    if (_fileFD >= 0) close(_fileFD);
    if (_directoryFD >= 0) close(_directoryFD);
    _queueFD = _fileFD = _directoryFD = -1;
    _poll = _debounce = _events = nil;
}
@end
