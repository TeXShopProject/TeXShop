#import "TSExperimentJob.h"
#include <signal.h>
#include <unistd.h>

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
