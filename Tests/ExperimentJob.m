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
    // The direct task exits while a descendant still holds the output pipe open.
    // Check the bytes at callback time, not after a later run-loop iteration.
    NSMutableData *delayed = [NSMutableData data];
    __block BOOL delayedDone = NO;
    __block NSData *atCompletion = nil;
    TSExperimentJob *delayedJob = start(@"printf head; (sleep 0.3; printf tail) & exit 0", delayed, ^(int status) {
        atCompletion = [delayed copy];
        delayedDone = YES;
    });
    BOOL completed = waitUntil(^BOOL{ return delayedDone; }, 3);
    [delayedJob cancel];
    check(completed, @"delayed pipe EOF completes");
    check([[[NSString alloc] initWithData:atCompletion encoding:NSUTF8StringEncoding] isEqualToString:@"headtail"],
          @"completion waits for descendant output and EOF");

    // A descendant announces readiness after installing its TERM trap and after
    // the direct task exits. Cancellation must still stop its process group.
    // Cancellation must give the entire group a chance to handle TERM, rather
    // than merely terminating the direct shell and later killing its children.
    NSString *marker = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *quotedMarker = [marker stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *gracefulScript = [NSString stringWithFormat:
        @"/bin/sh -c 'trap '\\''printf term > \"$1\"; exit 0'\\'' TERM; while kill -0 \"$2\" 2>/dev/null; do sleep 0.01; done; printf '\\''%%s\\n'\\'' $$; while :; do sleep 0.02; done' sh '%@' $$ & exit 0", quotedMarker];
    NSMutableData *gracefulOutput = [NSMutableData data];
    TSExperimentJob *graceful = start(gracefulScript, gracefulOutput, nil);
    BOOL gracefulReady = waitUntil(^BOOL{ return [gracefulOutput rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, gracefulOutput.length)].location != NSNotFound; }, 3);
    pid_t gracefulPID = [[[NSString alloc] initWithData:gracefulOutput encoding:NSUTF8StringEncoding] intValue];
    [graceful cancel];
    BOOL receivedTERM = [[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"term"];
    // Clean up the test-owned child even if an intentionally broken job left it running.
    if (gracefulPID > 1 && kill(gracefulPID, 0) == 0) kill(gracefulPID, SIGKILL);
    [[NSFileManager defaultManager] removeItemAtPath:marker error:NULL];
    check(gracefulReady && gracefulPID > 1, @"TERM-trapping descendant ready");
    check(receivedTERM, @"cancellation sends TERM to descendants before KILL");

    // Ignore TERM before creating the child so both processes require escalation.
    NSMutableData *stubbornOutput = [NSMutableData data];
    TSExperimentJob *stubborn = start(@"trap '' TERM; sleep 20 & printf '%s\\n' $!; wait", stubbornOutput, nil);
    BOOL stubbornReady = waitUntil(^BOOL{ return [stubbornOutput rangeOfData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0, stubbornOutput.length)].location != NSNotFound; }, 3);
    pid_t stubbornPID = [[[NSString alloc] initWithData:stubbornOutput encoding:NSUTF8StringEncoding] intValue];
    [stubborn cancel];
    BOOL childStopped = stubbornPID > 1 && waitUntil(^BOOL{ return kill(stubbornPID, 0) != 0; }, 2);
    if (stubbornPID > 1 && kill(stubbornPID, 0) == 0) kill(stubbornPID, SIGKILL);
    check(stubbornReady && stubbornPID > 1, @"TERM-ignoring descendant ready");
    check(childStopped, @"cancellation escalates to KILL for TERM-ignoring descendants");
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
    puts("PASS: independent interactive jobs, both completion orders, cancellation/replacement, normal task preservation, delayed EOF, group TERM, KILL escalation, output drain, launch failure");
} return 0; }
