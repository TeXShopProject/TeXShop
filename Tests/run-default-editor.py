#!/usr/bin/env python3
"""Make Default Editor asks the system for every content type of .tex files."""
from pathlib import Path
import subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/TSAppDelegate.m').read_text(encoding='latin-1')
start = source.index('- (void)makeDefaultEditor:(id)sender;')
method = source[start:source.index('\n}\n', start) + 3]
if 'LSSetDefaultRoleHandlerForContentType' in source:
    raise SystemExit('FAIL: the deprecated LaunchServices call is still used')
method = method.replace('[[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:', '[StubWorkspace() setDefaultApplicationAtURL:')
method = method.replace('[NSApp presentError: error];', 'Presented(error);')
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
if mutation == 'fixed-type':
    method = method.replace('[types addObjectsFromArray: [UTType typesWithTag: @"tex" tagClass: UTTagClassFilenameExtension conformingToType: nil]];', '')
    method = method.replace('[UTType typeWithFilenameExtension: @"tex"]', '[UTType typeWithIdentifier: @"edu.uo.texshop.tex"]')
program = r'''
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
@interface Stub : NSObject
@property (strong) NSMutableArray *calls;
@property (strong) NSError *reply;
@end
@implementation Stub
- (void)setDefaultApplicationAtURL:(NSURL *)url toOpenContentType:(UTType *)type completionHandler:(void (^)(NSError *))done {
    [self.calls addObject:@[url, type]];
    NSError *reply = self.reply;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{ done(reply); });
}
@end
static Stub *stub; static NSMutableArray *presented;
static Stub *StubWorkspace(void) { return stub; }
static void Presented(NSError *e) { [presented addObject:e]; }
@interface Delegate : NSObject @end
@implementation Delegate
METHOD
@end
static void Spin(void) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]]; }
int main(void) { @autoreleasepool {
    int failures = 0;
    UTType *tex = [UTType typeWithFilenameExtension:@"tex"];
    for (NSError *reply in @[[NSNull null], [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil], [NSError errorWithDomain:NSOSStatusErrorDomain code:-54 userInfo:nil]]) {
        stub = [Stub new]; stub.calls = [NSMutableArray array]; stub.reply = [reply isKindOfClass:NSError.class] ? reply : nil; presented = [NSMutableArray array];
        [[Delegate new] makeDefaultEditor:nil]; Spin();
        BOOL hasTex = NO; for (NSArray *c in stub.calls) if ([c[1] isEqual:tex]) hasTex = YES;
        if (!hasTex) { printf("FAIL: the type .tex files resolve to (%s) is not set\n", tex.identifier.UTF8String); failures++; }
        for (NSArray *c in stub.calls) if (![c[0] isEqual:NSBundle.mainBundle.bundleURL]) { printf("FAIL: wrong application URL\n"); failures++; break; }
        NSUInteger expected = (stub.reply && stub.reply.code != NSUserCancelledError) ? 1 : 0;
        if (presented.count != expected) { printf("FAIL: presented %lu errors, expected %lu\n", (unsigned long)presented.count, (unsigned long)expected); failures++; }
    }
    printf(".tex resolves to %s\n", tex.identifier.UTF8String);
    return failures ? 1 : 0;
} }
'''.replace('METHOD', method)
with tempfile.TemporaryDirectory(prefix='texshop-default-') as tmp:
    src, exe = Path(tmp) / 'test.m', Path(tmp) / 'test'
    src.write_text(program)
    subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Cocoa', '-framework', 'UniformTypeIdentifiers', str(src), '-o', str(exe)], check=True)
    r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)
    print(r.stdout.strip())
    if mutation:
        if r.returncode == 0: raise SystemExit('FAIL: mutation %s was not detected' % mutation)
        print('detected mutation', mutation)
    elif r.returncode: raise SystemExit(r.stderr or 'FAIL')
    else: print('PASS: every .tex content type is requested for this application; failures other than cancelling are reported')
