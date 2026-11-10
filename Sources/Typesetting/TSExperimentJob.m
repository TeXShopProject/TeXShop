#import "TSExperimentJob.h"
#include <signal.h>
#include <unistd.h>
#include <sys/clonefile.h>

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
    @try { return [self.input.fileHandleForWriting writeData:data error:error]; }
    @catch (NSException *exception) { return NO; }
}

// A folder with more items than this, counted through its subfolders, is not cloned, so that an
// Experiment starts quickly.
static const NSUInteger TSExperimentMaximumClonedItems = 5000;

// Removes the symbolic links under `directory` that lead out of it: TeX writing through them would
// change files elsewhere. Links within the clones stay.
static void TSExperimentRemoveOutwardLinks(NSFileManager *manager, NSString *directory)
{
    NSString *base = [directory.stringByStandardizingPath stringByAppendingString:@"/"];
    NSMutableArray<NSString *> *outward = [NSMutableArray array];
    NSDirectoryEnumerator *walk = [manager enumeratorAtPath:directory];
    for (NSString *relative in walk) {
        if (![walk.fileAttributes[NSFileType] isEqual:NSFileTypeSymbolicLink]) continue;
        NSString *path = [directory stringByAppendingPathComponent:relative];
        NSString *target = [manager destinationOfSymbolicLinkAtPath:path error:NULL];
        if (target && !target.isAbsolutePath)
            target = [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:target];
        if (!target || ![[target.stringByStandardizingPath stringByAppendingString:@"/"] hasPrefix:base])
            [outward addObject:path];
    }
    for (NSString *path in outward) [manager removeItemAtPath:path error:NULL];
}

+ (NSUInteger)cloneItemsOfDirectory:(NSURL *)source intoDirectory:(NSURL *)directory exceptNames:(NSArray<NSString *> *)names
{
    if (!source || !directory) return 0;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSUInteger total = 0;
    for (__unused NSString *item in [manager enumeratorAtPath:source.path])
        if (++total > TSExperimentMaximumClonedItems) return 0;
    NSMutableSet<NSString *> *excluded = [NSMutableSet set];
    for (NSString *name in names) [excluded addObject:name.lowercaseString];
    NSUInteger count = 0;
    for (NSString *item in [manager contentsOfDirectoryAtPath:source.path error:NULL]) {
        NSString *lower = item.lowercaseString;
        // Names are compared ignoring case, as the file system may.
        if ([excluded containsObject:lower] || [lower hasPrefix:@"file."]) continue;
        NSString *from = [source.path stringByAppendingPathComponent:item];
        NSString *to = [directory.path stringByAppendingPathComponent:item];
        if ([manager fileExistsAtPath:to]) continue;
        if (clonefile(from.fileSystemRepresentation, to.fileSystemRepresentation, CLONE_NOFOLLOW | CLONE_NOOWNERCOPY) == 0)
            count++;
    }
    TSExperimentRemoveOutwardLinks(manager, directory.path);
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
