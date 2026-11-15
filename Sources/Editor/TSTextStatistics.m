// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * TSTextStatistics.m
 */

#import "TSTextStatistics.h"
#import <stdatomic.h>

@interface TSTextStatisticsResult ()
@property (nonatomic, readwrite) TSTextStatisticsState state;
@property (nonatomic, readwrite) BOOL selection;
@property (nonatomic, readwrite) TSStatusBarCounts source;
@property (nonatomic, readwrite) TSStatusBarCounts text;
@property (nonatomic, readwrite) NSDate *date;
@end

@implementation TSTextStatisticsResult
@end

// One count, which `stop` or a newer count cancels.
@interface TSTextStatisticsRun : NSObject
{
@public
    atomic_bool cancelled;
}
@property (nonatomic, strong, nullable) NSTask *task;
@property (nonatomic, strong, nullable) NSURL *file;
@end

@implementation TSTextStatisticsRun
@end

static void TSRemoveFile(NSURL *_Nullable file)
{
    NSString *path = file.path;
    if (path)
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
}

@interface TSTextStatistics ()
@property (nonatomic, strong, nullable) TSTextStatisticsRun *run;
@property (nonatomic) dispatch_queue_t queue;
@end

@implementation TSTextStatistics

+ (nullable NSURL *)detexInFolder:(nullable NSString *)binFolder
{
    if (binFolder.length == 0)
        return nil;
    NSString *path = [[binFolder stringByExpandingTildeInPath] stringByAppendingPathComponent:@"detex"];
    return [NSFileManager.defaultManager isExecutableFileAtPath:path] ? [NSURL fileURLWithPath:path] : nil;
}

+ (NSString *)countedTextOfString:(NSString *)string ranges:(NSArray<NSValue *> *)ranges selection:(BOOL *)selection
{
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSValue *value in ranges) {
        NSRange range = NSIntersectionRange(value.rangeValue, NSMakeRange(0, string.length));
        if (range.length > 0)
            [parts addObject:[string substringWithRange:range]];
    }
    if (selection)
        *selection = parts.count > 0;
    return parts.count ? [parts componentsJoinedByString:@"\n"] : [string copy];
}

- (instancetype)init
{
    if ((self = [super init]))
        _queue = dispatch_queue_create("TeXShop.textStatistics", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    return self;
}

- (void)dealloc
{
    [self stop];
}

- (BOOL)isRunning
{
    return self.run != nil;
}

- (nullable NSURL *)temporaryFile
{
    return self.run.file;
}

- (void)stop
{
    TSTextStatisticsRun *run = self.run;
    self.run = nil;
    if (!run)
        return;
    atomic_store(&run->cancelled, true);
    @synchronized (run) {
        if (run.task.isRunning)
            [run.task terminate];
    }
}

- (void)countString:(NSString *)string ranges:(NSArray<NSValue *> *)ranges folder:(nullable NSURL *)folder
              detex:(nullable NSURL *)detex encoding:(NSStringEncoding)encoding
         completion:(void (^)(TSTextStatisticsResult *result))completion
{
    [self stop];
    BOOL selection = NO;
    NSString *text = [TSTextStatistics countedTextOfString:string ranges:ranges selection:&selection];
    TSTextStatisticsRun *run = [TSTextStatisticsRun new];
    self.run = run;
    NSDate *date = [NSDate date];
    NSURL *directory = folder ?: [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    // A name of its own in the temporary folder; detex runs in the document's folder for \input and \include.
    NSString *name = [NSString stringWithFormat:@"TeXShop-statistics-%@.tex", NSUUID.UUID.UUIDString];
    NSURL *file = detex ? [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]] : nil;
    run.file = file;
    __weak TSTextStatistics *weakSelf = self;
    dispatch_async(self.queue, ^{
        TSStatusBarCounts source = TSStatusBarCountsUnknown(), body = TSStatusBarCountsUnknown();
        TSStatusBarCount(text, @[], YES, NO, &source, ^BOOL{ return atomic_load(&run->cancelled); });
        TSTextStatisticsState state = TSTextStatisticsDetexMissing;
        if (detex && !atomic_load(&run->cancelled)) {
            state = TSTextStatisticsDetexFailed;
            NSData *data = [text dataUsingEncoding:encoding allowLossyConversion:YES] ?: [text dataUsingEncoding:NSUTF8StringEncoding];
            if ([data writeToURL:(NSURL *_Nonnull)file atomically:NO]) {
                NSTask *task = [NSTask new];
                task.executableURL = detex;
                task.arguments = @[file.path ?: name];
                task.currentDirectoryURL = directory;
                NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
                NSString *bin = detex.URLByDeletingLastPathComponent.path ?: @"/usr/bin";
                environment[@"PATH"] = environment[@"PATH"] ? [NSString stringWithFormat:@"%@:%@", bin, environment[@"PATH"]] : bin;
                task.environment = environment;
                NSPipe *output = [NSPipe pipe];
                task.standardOutput = output;
                task.standardError = NSFileHandle.fileHandleWithNullDevice;
                task.standardInput = NSFileHandle.fileHandleWithNullDevice;
                BOOL launched = NO;
                @synchronized (run) {
                    if (!atomic_load(&run->cancelled)) {
                        run.task = task;
                        launched = [task launchAndReturnError:NULL];
                    }
                }
                if (launched) {
                    NSData *result = [output.fileHandleForReading readDataToEndOfFile];
                    [task waitUntilExit];
                    if (!atomic_load(&run->cancelled) && task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 0) {
                        NSString *stripped = [[NSString alloc] initWithData:result encoding:encoding]
                            ?: [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding]
                            ?: [[NSString alloc] initWithData:result encoding:NSISOLatin1StringEncoding];
                        if (stripped && TSStatusBarCount(stripped, @[], YES, NO, &body, ^BOOL{ return atomic_load(&run->cancelled); }))
                            state = TSTextStatisticsDone;
                    }
                }
            }
        }
        TSRemoveFile(file);
        if (atomic_load(&run->cancelled))
            return;
        TSTextStatisticsResult *done = [TSTextStatisticsResult new];
        done.state = state;
        done.selection = selection;
        done.source = source;
        done.text = state == TSTextStatisticsDone ? body : TSStatusBarCountsUnknown();
        done.date = date;
        dispatch_async(dispatch_get_main_queue(), ^{
            TSTextStatistics *strongSelf = weakSelf;
            if (atomic_load(&run->cancelled) || (strongSelf && strongSelf.run != run))
                return;
            if (strongSelf)
                strongSelf.run = nil;
            completion(done);
        });
    });
}

@end
