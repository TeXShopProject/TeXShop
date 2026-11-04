// added by Terada
#import "TSFileChangeMonitor.h"
#import <sys/event.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *TSFileStamp(NSString *path)
{
    struct stat s;
    if (stat(path.fileSystemRepresentation, &s) != 0) return nil;
    return [NSString stringWithFormat:@"%llu/%llu/%lld/%lld:%ld/%lld:%ld",
            (unsigned long long)s.st_dev, (unsigned long long)s.st_ino,
            (long long)s.st_size, (long long)s.st_mtimespec.tv_sec, s.st_mtimespec.tv_nsec,
            (long long)s.st_ctimespec.tv_sec, s.st_ctimespec.tv_nsec];
}

@implementation TSFileChangeMonitor {
    int _queueFD, _fileFD, _directoryFD;
    dispatch_source_t _events, _poll, _debounce;
    BOOL _stopped, _pending;
    NSString *_stamp;
    BOOL (^_reload)(void);
}

- (instancetype)initWithPath:(NSString *)path reload:(BOOL (^)(void))reload
{
    NSAssert([NSThread isMainThread], @"File monitoring must start on the main thread");
    self = [super init];
    if (!self) return nil;
    _queueFD = _fileFD = _directoryFD = -1;
    _path = [path.stringByStandardizingPath copy];
    _reload = [reload copy];
    _queueFD = kqueue();
    if (_queueFD < 0) return nil;
    fcntl(_queueFD, F_SETFD, FD_CLOEXEC);
    // kevent installs filters synchronously. dispatch_resume alone does not
    // guarantee that a vnode source is registered before the first file read.
    [self attachPath:_path.stringByDeletingLastPathComponent descriptor:&_directoryFD];
    [self attachPath:_path descriptor:&_fileFD];
    _stamp = TSFileStamp(_path);
    __weak TSFileChangeMonitor *weakSelf = self;
    _events = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _queueFD, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(_events, ^{ [weakSelf consumeEvents]; });
    int queueFD = _queueFD;
    dispatch_source_set_cancel_handler(_events, ^{ close(queueFD); });
    dispatch_resume(_events);
    _debounce = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_debounce, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(_debounce, ^{ [weakSelf attemptReload]; });
    dispatch_resume(_debounce);
    // This fallback reads metadata only, even for very large documents. It also
    // reconnects after a parent directory disappears and retries deferred reads.
    _poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_poll, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                             2 * NSEC_PER_SEC, NSEC_PER_SEC / 5);
    dispatch_source_set_event_handler(_poll, ^{
        TSFileChangeMonitor *monitor = weakSelf;
        if (!monitor || monitor->_stopped) return;
        BOOL changed = [monitor refresh];
        if (changed) [monitor markChanged];
        else if (monitor->_pending) [monitor attemptReload];
    });
    dispatch_resume(_poll);
    return self;
}

- (void)attachPath:(NSString *)path descriptor:(int *)descriptor
{
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
    _pending = YES;
    dispatch_source_set_timer(_debounce, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10),
                             DISPATCH_TIME_FOREVER, NSEC_PER_MSEC * 10);
}

- (void)attemptReload
{
    if (_stopped || !_pending) return;
    if ([self refresh]) { [self markChanged]; return; }
    if (!_stamp) return; // Keep the document and wait for a replacement.
    _pending = NO;
    BOOL (^reload)(void) = _reload;
    if (reload && !reload() && !_stopped) _pending = YES;
    // Filters stay registered while reload executes. Events queued during the
    // read are consumed afterwards, including writes that restore timestamps.
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
    _reload = nil;
}

- (void)dealloc { [self stop]; }
@end
