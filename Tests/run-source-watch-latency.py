#!/usr/bin/env python3
"""Regression: a second vnode event while accept blocks must not wait for polling."""
import subprocess, tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
program=r'''
#import <Foundation/Foundation.h>
#import "TSFileChangeMonitor.h"
static void Pump(double seconds){[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];}
static void Write(NSString *path,NSString *text){[text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];}
int main(int argc,char **argv){@autoreleasepool{
 NSString *path=@(argv[1]);Write(path,@"initial");
 __block BOOL initial=NO,second=NO;__block double completed=0,latency=99;
 TSFileChangeMonitor *monitor=[[TSFileChangeMonitor alloc]initWithPath:path prepare:^NSNumber*{return @0;} accept:^BOOL(NSData *data,NSData *hash,NSNumber *generation){
  NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
  if([text isEqual:@"initial"])initial=YES;
  if([text isEqual:@"first"]){
   Write(path,@"second");[NSThread sleepForTimeInterval:.4];completed=NSProcessInfo.processInfo.systemUptime;
  }
  if([text isEqual:@"second"]){second=YES;latency=NSProcessInfo.processInfo.systemUptime-completed;}
  return YES;
 }];
 for(int i=0;i<100&&!initial;i++)Pump(.01);
 if(!initial)return 2;
 Write(path,@"first");
 for(int i=0;i<250&&!second;i++)Pump(.01);
 [monitor stop];Pump(.1);
 printf("second=%d latency=%.3fs\n",second,latency);
 return second && latency<.8 ? 0 : 3;
}}
'''
with tempfile.TemporaryDirectory(prefix='texshop-watch-latency-') as td:
    t=Path(td);(t/'test.m').write_text(program)
    source=(root/'Sources/TSFileChangeMonitor.m').read_text()
    for mutation in [False,True]:
        s=source
        if mutation:
            a=s.index('                // A debounce may have fired')
            b=s.index('\n            });',a)
            s=s[:a]+s[b:]
        (t/'monitor.m').write_text(s)
        subprocess.run(['xcrun','clang','-w','-fobjc-arc','-framework','Foundation','-I'+str(root/'Sources'),str(t/'test.m'),str(t/'monitor.m'),'-o',str(t/'test')],check=True)
        for repeat in range(3):
            result=subprocess.run([str(t/'test'),str(t/'test.tex')],text=True,capture_output=True)
            print(('mutation' if mutation else 'production'),result.stdout.strip(),flush=True)
            assert result.returncode==(3 if mutation else 0),result.stderr
    print('PASS: prompt second update; regression detected in all three controls')
