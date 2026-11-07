#import <Foundation/Foundation.h>
#import "TSExperimentJob.h"
#include <signal.h>
#include <unistd.h>

static void check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static BOOL waitUntil(BOOL (^condition)(void), double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && end.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}
static TSExperimentJob *start(NSString *script, NSMutableData *output, void (^done)(int)) {
    TSExperimentJob *job = [[TSExperimentJob alloc] init];
    job.outputHandler = ^(NSData *data) { [output appendData:data]; };
    job.completionHandler = done;
    NSError *error;
    check([job startExecutable:@"/bin/sh" arguments:@[@"-c",script]
                environment:@{@"PATH":@"/usr/bin:/bin"} directory:[NSURL fileURLWithPath:NSTemporaryDirectory()] error:&error], error.description);
    return job;
}
int main(void) { @autoreleasepool {
    // Two simultaneous interactive jobs. Each console must receive only its own data,
    // and EOF must be drained before the completion callback.
    for (NSUInteger reverse = 0; reverse < 2; reverse++) {
        NSMutableData *a = [NSMutableData data], *b = [NSMutableData data];
        __block BOOL doneA = NO, doneB = NO;
        TSExperimentJob *first = start(@"printf 'A ready\\n'; read input; printf 'A:%s\\n' \"$input\"", a, ^(int status) { check(status == 0, @"A status"); doneA = YES; });
        TSExperimentJob *second = start(@"printf 'B ready\\n'; read input; printf 'B:%s\\n' \"$input\"", b, ^(int status) { check(status == 0, @"B status"); doneB = YES; });
        check(waitUntil(^BOOL{ return a.length > 0 && b.length > 0; }, 3), @"both prompts");
        TSExperimentJob *early = reverse ? second : first, *late = reverse ? first : second;
        check([early sendData:[@"early\n" dataUsingEncoding:NSUTF8StringEncoding] error:NULL], @"first input");
        check(waitUntil(^BOOL{ return reverse ? doneB : doneA; }, 3), @"early finishes");
        check(late.active && !(reverse ? doneA : doneB), @"other job still active");
        check([late sendData:[@"late\n" dataUsingEncoding:NSUTF8StringEncoding] error:NULL], @"other input");
        check(waitUntil(^BOOL{ return doneA && doneB; }, 3), @"both complete");
        NSString *sa = [[NSString alloc] initWithData:a encoding:NSUTF8StringEncoding];
        NSString *sb = [[NSString alloc] initWithData:b encoding:NSUTF8StringEncoding];
        check([sa isEqualToString:reverse ? @"A ready\nA:late\n" : @"A ready\nA:early\n"], sa);
        check([sb isEqualToString:reverse ? @"B ready\nB:early\n" : @"B ready\nB:late\n"], sb);
    }
    // Simulate the ordinary TeX task with a completely independent NSTask and input
    // pipe; stopping/replacing an Experiment must not close them or kill that task.
    NSTask *ordinary = [[NSTask alloc] init];
    ordinary.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    ordinary.arguments = @[@"-c", @"read line; printf 'ordinary:%s' \"$line\""];
    NSPipe *ordinaryInput = [NSPipe pipe], *ordinaryOutput = [NSPipe pipe];
    ordinary.standardInput = ordinaryInput; ordinary.standardOutput = ordinaryOutput;
    check([ordinary launchAndReturnError:NULL], @"ordinary launch");
    __block BOOL cancelledCallback = NO;
    NSMutableData *childOutput = [NSMutableData data];
    TSExperimentJob *cancelled = start(@"sleep 20 & printf '%s\\n' $!; wait", childOutput, ^(int status) { cancelledCallback = YES; });
    check(waitUntil(^BOOL{ return childOutput.length > 0; }, 3), @"child process started");
    pid_t child = [[[NSString alloc] initWithData:childOutput encoding:NSUTF8StringEncoding] intValue];
    check(child > 1 && kill(child, 0) == 0, @"child running before cancellation");
    [cancelled cancel];
    check(waitUntil(^BOOL{ return kill(child, 0) != 0; }, 3), @"Experiment child terminated");
    check(ordinary.running, @"Experiment cancellation leaves ordinary running");
    __block BOOL replacementDone = NO;
    NSMutableData *replacementOutput = [NSMutableData data];
    TSExperimentJob *replacement = start(@"printf replacement", replacementOutput, ^(int status) { replacementDone = YES; });
    check(waitUntil(^BOOL{ return replacementDone; }, 3), @"replacement completes");
    check(!cancelledCallback, @"cancelled completion never fires");
    [ordinaryInput.fileHandleForWriting writeData:[@"still here\n" dataUsingEncoding:NSUTF8StringEncoding]];
    check(waitUntil(^BOOL{ return !ordinary.running; }, 3), @"ordinary completes after input");
    NSData *normalData = [ordinaryOutput.fileHandleForReading readDataToEndOfFile];
    check([[[NSString alloc] initWithData:normalData encoding:NSUTF8StringEncoding] isEqualToString:@"ordinary:still here"], @"ordinary input/output preserved");
    (void)replacement;
    // Large output exceeds pipe capacity: completion must not lose the tail or block.
    NSMutableData *large = [NSMutableData data];
    __block BOOL largeDone = NO;
    TSExperimentJob *largeJob = start(@"/usr/bin/head -c 1048576 /dev/zero; printf END", large, ^(int status) { largeDone = YES; });
    check(waitUntil(^BOOL{ return largeDone; }, 10), @"large output completes");
    check(large.length == 1048579 && memcmp((char *)large.bytes + large.length - 3, "END", 3) == 0, @"output drained before completion");
    (void)largeJob;
    TSExperimentJob *bad = [[TSExperimentJob alloc] init];
    NSError *error = nil;
    check(![bad startExecutable:@"/nonexistent/texshop-test-engine" arguments:@[] environment:@{} directory:[NSURL fileURLWithPath:NSTemporaryDirectory()] error:&error], @"launch failure reported");
    check(error != nil && !bad.active && ![bad sendData:NSData.data error:NULL], @"failed job cannot take input");
    [bad cancel];
    puts("PASS: independent interactive jobs, both completion orders, cancellation/replacement, normal task preservation, output drain, launch failure");
} return 0; }
