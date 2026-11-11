#import "TSExperimentJob.h"
#import "TSConsoleOutput.h"
#include <signal.h>
#include <unistd.h>
#include <sys/clonefile.h>
#include <sys/stat.h>

@interface TSExperimentJob ()
@property (nonatomic, strong) NSTask *task;
@property (nonatomic, strong) NSPipe *input;
@property (nonatomic, strong) NSPipe *output;
@property (nonatomic, strong) id readObserver;
@property (nonatomic) pid_t processGroup;
@property (nonatomic) BOOL launched;
@property (nonatomic) BOOL finished;
@property (nonatomic) BOOL reachedEOF;
@property (nonatomic) BOOL terminated;
@property (nonatomic) int status;
@end

@implementation TSExperimentJob
- (BOOL)isActive { return self.launched && !self.finished; }

- (void)closeHandles
{
    if (self.readObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.readObserver];
        self.readObserver = nil;
    }
    for (NSFileHandle *handle in @[self.input.fileHandleForWriting ?: NSNull.null,
                                   self.output.fileHandleForReading ?: NSNull.null]) {
        if ((id)handle != NSNull.null) {
            @try { [handle closeFile]; } @catch (NSException *exception) { }
        }
    }
    self.input = nil;
    self.output = nil;
}

- (void)finishIfReady
{
    if (self.finished || !self.terminated || !self.reachedEOF)
        return;
    self.finished = YES;
    self.task.terminationHandler = nil;
    self.processGroup = 0;
    [self closeHandles];
    void (^completion)(int) = self.completionHandler;
    self.completionHandler = nil;
    self.outputHandler = nil;
    if (completion) completion(self.status);
}

- (void)readMore
{
    if (self.finished) return;
    @try {
        [self.output.fileHandleForReading readInBackgroundAndNotify];
    } @catch (NSException *exception) {
        self.reachedEOF = YES;
        [self finishIfReady];
    }
}

- (BOOL)startExecutable:(NSString *)path arguments:(NSArray<NSString *> *)arguments
           environment:(NSDictionary<NSString *,NSString *> *)environment
             directory:(NSURL *)directory error:(NSError **)error
{
    NSAssert(NSThread.isMainThread, @"Experiment jobs must start on the main thread");
    if (self.launched || self.finished) return NO;
    self.task = [[NSTask alloc] init];
    self.task.executableURL = [NSURL fileURLWithPath:path];
    self.task.arguments = arguments;
    self.task.environment = environment;
    self.task.currentDirectoryURL = directory;
    self.input = [NSPipe pipe];
    self.output = [NSPipe pipe];
    self.task.standardInput = self.input;
    self.task.standardOutput = self.output;
    self.task.standardError = self.output;
    __weak TSExperimentJob *weakSelf = self;
    self.readObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSFileHandleReadCompletionNotification
        object:self.output.fileHandleForReading queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            TSExperimentJob *job = weakSelf;
            if (!job || job.finished) return;
            NSData *data = notification.userInfo[NSFileHandleNotificationDataItem];
            if (data.length) {
                if (job.outputHandler) job.outputHandler(data);
                [job readMore];
            } else {
                job.reachedEOF = YES;
                [job finishIfReady];
            }
        }];
    self.task.terminationHandler = ^(NSTask *task) {
        dispatch_async(dispatch_get_main_queue(), ^{
            TSExperimentJob *job = weakSelf;
            if (!job || job.finished) return;
            job.terminated = YES;
            job.status = task.terminationStatus;
            [job finishIfReady];
        });
    };
    BOOL success = NO;
    @try { success = [self.task launchAndReturnError:error]; }
    @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError
                                           userInfo:@{NSLocalizedDescriptionKey:exception.reason ?: @"Cannot start Experiment"}];
    }
    if (!success) {
        self.task.terminationHandler = nil;
        self.finished = YES;
        self.completionHandler = nil;
        self.outputHandler = nil;
        [self closeHandles];
        return NO;
    }
    self.launched = YES;
    pid_t pid = self.task.processIdentifier;
    pid_t group = getpgid(pid);
    if (pid > 1 && group == pid && group != getpgrp()) self.processGroup = group;
    [self readMore];
    return YES;
}

- (BOOL)sendData:(NSData *)data error:(NSError **)error
{
    if (!self.active || !self.task.running || !data) return NO;
    return TSWriteConsoleInput(self.input.fileHandleForWriting, data, error);
}

// A folder with more items than this, counted through its subfolders, is not cloned, so that an
// Experiment starts quickly.
static const NSUInteger TSExperimentMaximumClonedItems = 5000;

// Whether a symbolic link can only lead further down the clone: its target is relative and has
// no .. component. Such a link is made again in the Experiment folder; any other one could lead
// out of it and is left out.
static BOOL TSExperimentLinkLeadsDown(NSString *target)
{
    return target.length && !target.isAbsolutePath && ![target.pathComponents containsObject:@".."];
}

+ (NSUInteger)cloneItemsOfDirectory:(NSURL *)source intoDirectory:(NSURL *)directory exceptNames:(NSArray<NSString *> *)names
{
    if (!source || !directory) return 0;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSString *item in [manager enumeratorAtPath:source.path]) {
        if (items.count == TSExperimentMaximumClonedItems) return 0;
        [items addObject:item];
    }
    NSMutableSet<NSString *> *excluded = [NSMutableSet set];
    for (NSString *name in names) [excluded addObject:name.lowercaseString];
    // Folders are made anew and only files are cloned: cloning a whole folder can take seconds in
    // a folder that a file provider such as Dropbox keeps, while cloning its files one by one does
    // not. The folders made here, listed relative to the Experiment folder, belong to their owner.
    NSMutableSet<NSString *> *folders = [NSMutableSet setWithObject:@""];
    NSUInteger count = 0;
    for (NSString *item in items) {
        NSString *parent = item.stringByDeletingLastPathComponent;
        if (![folders containsObject:parent]) continue; // inside a folder that is left out
        NSString *lower = item.lowercaseString;
        // Names are compared ignoring case, as the file system may.
        if (!parent.length && ([excluded containsObject:lower] || [lower hasPrefix:@"file."])) continue;
        NSString *from = [source.path stringByAppendingPathComponent:item];
        NSString *to = [directory.path stringByAppendingPathComponent:item];
        struct stat info;
        if (lstat(from.fileSystemRepresentation, &info) != 0) continue;
        if (S_ISDIR(info.st_mode)) {
            if (mkdir(to.fileSystemRepresentation, 0700) != 0) continue;
            chmod(to.fileSystemRepresentation, (info.st_mode & 0777) | 0700);
            [folders addObject:item];
            count++;
        } else if (S_ISLNK(info.st_mode)) {
            NSString *target = [manager destinationOfSymbolicLinkAtPath:from error:NULL];
            if (TSExperimentLinkLeadsDown(target) && symlink(target.fileSystemRepresentation, to.fileSystemRepresentation) == 0)
                count++;
        } else if (S_ISREG(info.st_mode)) {
            // A file whose contents are not on this Mac, such as an online-only Dropbox file, is
            // not downloaded for the clone; TeX finds it through TEXINPUTS when it reads it.
            if (info.st_flags & SF_DATALESS) continue;
            if (clonefile(from.fileSystemRepresentation, to.fileSystemRepresentation, CLONE_NOFOLLOW | CLONE_NOOWNERCOPY) == 0)
                count++;
        }
    }
    return count;
}

+ (BOOL)copyAuxiliaryFile:(NSURL *)aux toURL:(NSURL *)destination
{
    NSData *data = aux ? [NSData dataWithContentsOfURL:aux] : nil;
    if (!data.length) return NO;
    const char *bytes = data.bytes;
    NSUInteger end = data.length;
    while (end > 0 && bytes[end - 1] != '\n') end--;
    if (end == 0) return NO;
    return [[data subdataWithRange:NSMakeRange(0, end)] writeToURL:destination atomically:YES];
}

- (void)cancel
{
    self.finished = YES; // Invalidate queued output/completion before stopping this job.
    self.task.terminationHandler = nil;
    self.outputHandler = nil;
    self.completionHandler = nil;
    pid_t group = self.processGroup;
    if (group <= 1 || group == getpgrp() || kill(-group, 0) != 0) group = 0;
    if (group) kill(-group, SIGTERM);
    else if (self.task.running) [self.task terminate];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
    while ((self.task.running || (group && kill(-group, 0) == 0)) && deadline.timeIntervalSinceNow > 0)
        [NSThread sleepForTimeInterval:0.01];
    if (group && kill(-group, 0) == 0) kill(-group, SIGKILL);
    if (self.task.running && self.task.processIdentifier > 1) kill(self.task.processIdentifier, SIGKILL);
    self.processGroup = 0;
    [self closeHandles];
}

- (void)dealloc { [self cancel]; }
@end
