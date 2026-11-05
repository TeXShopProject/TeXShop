#!/usr/bin/env python3
"""Exceptions from monitor callbacks must not escape and must not stop monitoring.
Monitoring started or stopped off the main thread must keep working. Each check
is also run against a mutated monitor to show that it detects the regression.
"""
import subprocess, tempfile
from pathlib import Path
root = Path(__file__).resolve().parents[1]
program = r'''
#import <Foundation/Foundation.h>
#import "TSFileChangeMonitor.h"
static void Pump(double seconds){NSDate *t=[NSDate dateWithTimeIntervalSinceNow:seconds];while(t.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
static void Write(NSString *path,NSString *text){[text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];}
// Run on a background thread; dispatch_sync could run the block on the caller.
static void OffMain(dispatch_block_t block){dispatch_semaphore_t s=dispatch_semaphore_create(0);dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{block();dispatch_semaphore_signal(s);});dispatch_semaphore_wait(s,DISPATCH_TIME_FOREVER);}
static NSString *Text(NSData *data){return [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];}
int main(int argc,char **argv){@autoreleasepool{
 NSString *path=@(argv[1]),*mode=@(argv[2]);Write(path,@"initial");
 __block NSMutableArray *seen=[NSMutableArray new];__block BOOL offMain=NO,throwPrepare=NO;__block int prepares=0;
 NSNumber *(^prepare)(void)=^NSNumber*{
  if(!NSThread.isMainThread)offMain=YES;
  prepares++;
  if(throwPrepare){throwPrepare=NO;[NSException raise:@"TSProbeException" format:@"prepare"];}
  return @0;
 };
 BOOL (^accept)(NSData *,NSData *,NSNumber *)=^BOOL(NSData *data,NSData *hash,NSNumber *generation){
  if(!NSThread.isMainThread)offMain=YES;
  NSString *text=Text(data);[seen addObject:text];
  if([mode isEqual:@"accept"]&&[text isEqual:@"first"])[NSException raise:@"TSProbeException" format:@"accept"];
  return YES;
 };
 __block TSFileChangeMonitor *monitor=nil;
 if([mode isEqual:@"off-main"]){
  __block NSString *failure=nil;__block BOOL background=NO;
  OffMain(^{
   background=!NSThread.isMainThread;
   @try{monitor=[[TSFileChangeMonitor alloc]initWithPath:path prepare:prepare accept:accept];}
   @catch(NSException *e){failure=e.reason;}
  });
  if(!background)return 2;
  if(failure){printf("off-main created=0 reason=%s\n",failure.UTF8String);return 3;}
 } else monitor=[[TSFileChangeMonitor alloc]initWithPath:path prepare:prepare accept:accept];
 for(int i=0;i<100&&![seen containsObject:@"initial"];i++)Pump(.01);
 if(![seen containsObject:@"initial"])return 2;
 if([mode isEqual:@"prepare"])throwPrepare=YES;
 Write(path,@"first");
 for(int i=0;i<300&&![seen containsObject:@"first"];i++)Pump(.01);
 Pump(.3);
 Write(path,@"second");
 for(int i=0;i<300&&![seen containsObject:@"second"];i++)Pump(.01);
 BOOL first=[seen containsObject:@"first"],second=[seen containsObject:@"second"];
 NSUInteger count=seen.count;
 if([mode isEqual:@"off-main"]){
  OffMain(^{[monitor stop];});
  Pump(.2);
 } else [monitor stop];
 Write(path,@"after stop");Pump(2.5);
 BOOL quiet=seen.count==count;
 printf("%s first=%d second=%d prepares=%d mainThreadOnly=%d quietAfterStop=%d\n",mode.UTF8String,first,second,prepares,!offMain,quiet);
 return first&&second&&!offMain&&quiet?0:3;
}}
'''
# Each mutation reintroduces the behaviour fixed for one scenario.
mutations = {
    'accept': ('            @try {\n                accepted = [self.owner acceptData:data fingerprint:fingerprint generation:generation];\n'
               '            } @catch (NSException *exception) {\n',
               '            {\n                accepted = [self.owner acceptData:data fingerprint:fingerprint generation:generation];\n'
               '            } if (0) { NSException *exception = nil;\n'),
    'prepare': ('    @try {\n        generation = !_stopped && _prepare ? _prepare() : nil;\n    } @catch (NSException *exception) {\n',
                '    {\n        generation = !_stopped && _prepare ? _prepare() : nil;\n    } if (0) { NSException *exception = nil;\n'),
    'off-main': ('    if (!(self = [super init])) return nil;\n',
                 '    NSAssert(NSThread.isMainThread, @"Start monitoring on the main thread");\n    if (!(self = [super init])) return nil;\n'),
}
with tempfile.TemporaryDirectory(prefix='texshop-watch-exceptions-') as td:
    t = Path(td); (t/'test.m').write_text(program)
    source = (root/'Sources/TSFileChangeMonitor.m').read_text()
    for mutated in [False, True]:
        for mode, (old, new) in mutations.items():
            s = source
            if mutated:
                if s.count(old) != 1: raise SystemExit(f'{mode}: mutation replacement count')
                s = s.replace(old, new)
            (t/'monitor.m').write_text(s)
            exe = t/'test'
            subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Foundation', '-I'+str(root/'Sources'),
                            str(t/'test.m'), str(t/'monitor.m'), '-o', str(exe)], check=True)
            result = subprocess.run([str(exe), str(t/'test.tex'), mode], text=True, capture_output=True, timeout=30)
            label = 'mutation' if mutated else 'production'
            print(label, mode, result.stdout.strip() or f'exit={result.returncode}', flush=True)
            if mutated:
                if result.returncode == 0: raise SystemExit(f'FAIL: mutation of {mode} not detected')
            elif result.returncode != 0:
                raise SystemExit(f'FAIL {mode}: {result.stderr}')
    print(f'PASS: {len(mutations)} callback exception and thread scenarios; all mutations detected')
