#!/usr/bin/env python3
"""An AppleScript macro run by ScriptRunner is written inside the temporary folder and run only when it was written.

Production statements of -[TSMacroMenuController doMacro:] (Sources/Macros/TSMacroMenuController.m), from the folder
of the script to the start of ScriptRunner, run with a folder of the test and a stand-in for ScriptRunner:
- the script lands in the temporary folder (NSTemporaryDirectory() ends in "/", which -stringByStandardizingPath drops);
- a script that cannot be written is not run;
- a ScriptRunner that is missing or cannot be started does not raise, and its script is removed.
Also: the macros are checked and read from the same bytes, and texdoc is started without a call that raises.
Nothing is shown on screen. --mutations checks that the guards are needed."""
import os, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import verify_embedded

root = Path(__file__).resolve().parents[1]
menu = (root/'Sources/Macros/TSMacroMenuController.m').read_text()
help_documents = (root/'Sources/App/HelpDocuments.m').read_text()
first = '            NSString *scriptFilePath = [[GlobalData sharedGlobalData].tempAppleScriptPath stringByStandardizingPath];'
last = '[[NSFileManager defaultManager] removeItemAtPath: scriptFileName error: NULL];\n\t\t\t\tNSBeep();\n\t\t\t}\n'
start = menu.index(first); end = menu.index(last, start) + len(last)
statements = menu[start:end]
assert menu.count(statements) == 1
fragments = [('statements: from the folder of the script to ScriptRunner', menu, statements)]

# The macros: the bytes that are checked are the bytes that are used.
load = menu[menu.index('- (void)loadMacros'):]
load = load[:load.index('\n}\n')]
assert 'TSLibraryFileIsUsable' not in load and 'macrosCheck(candidateData, nil)' in load and 'myData = candidateData;' in load, \
    'loadMacros checks the data it uses'
# texdoc: started with -launchAndReturnError:, never -launch.
assert '[displayPackageHelpTask launch]' not in help_documents and '[displayPackageHelpTask launchAndReturnError:NULL]' in help_documents, \
    'texdoc is started without raising'
assert '[scriptTask launch]' not in menu, 'ScriptRunner is started without raising'

MUTATIONS = {
    'append-string': ('[scriptFilePath stringByAppendingPathComponent: globallyUniqueString]', '[scriptFilePath stringByAppendingString: globallyUniqueString]'),
    'run-unwritten': ('\t\t\tif (! written) {\n\t\t\t\tNSBeep();\n\t\t\t\treturn;\n\t\t\t}', '\t\t\tif (NO) {\n\t\t\t}'),
    'missing-runner-leaves-script': ('\t\t\tif (runnerPath == nil) {\n\t\t\t\t[[NSFileManager defaultManager] removeItemAtPath: scriptFileName error: NULL];', '\t\t\tif (runnerPath == nil) {\n'),
    'launch-raises': ('if (! [scriptTask launchAndReturnError: NULL]) {', '[scriptTask launch]; if (NO) {'),
}

PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
@interface GlobalData : NSObject
@property (retain) NSString *tempAppleScriptPath;
+ (GlobalData *)sharedGlobalData;
@end
@implementation GlobalData
+ (GlobalData *)sharedGlobalData { static GlobalData *shared; if (!shared) shared = [GlobalData new]; return shared; }
@end
static NSString *runner; static NSUInteger runnerLookups;
static NSString *RunnerPath(id self, SEL cmd, NSString *name, NSString *type, NSString *directory) { runnerLookups++; return runner; }
static void RunScript(NSString *newString)
{
    NSMutableArray *args;
STATEMENTS
}
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); } }
static NSArray *Contents(NSString *folder) { return [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL] ?: @[]; }
int main(int argc, char **argv) { @autoreleasepool {
    method_setImplementation(class_getInstanceMethod(NSBundle.class, @selector(pathForResource:ofType:inDirectory:)), (IMP)RunnerPath);
    NSString *base = @(argv[1]);
    NSString *folder = [base stringByAppendingPathComponent:@"Temp"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];

    // As TeXShop sets it: the temporary folder with "/" at its end.
    [GlobalData sharedGlobalData].tempAppleScriptPath = [folder stringByAppendingString:@"/"];
    runner = @"/usr/bin/true";
    RunScript(@"-- macro");
    NSArray *written = Contents(folder);
    Check(written.count == 1, [NSString stringWithFormat:@"the script is in the temporary folder: %@ (beside it: %@)", written, Contents(base)]);
    Check(written.count == 1 && [[NSString stringWithContentsOfFile:[folder stringByAppendingPathComponent:written.firstObject] encoding:NSUTF8StringEncoding error:NULL] isEqual:@"-- macro"], @"the script holds the macro");
    Check(Contents(base).count == 1, @"nothing beside the temporary folder");

    // A folder that cannot be written to: nothing is run.
    [GlobalData sharedGlobalData].tempAppleScriptPath = [base stringByAppendingPathComponent:@"Missing/"];
    runnerLookups = 0;
    RunScript(@"-- macro");
    Check(runnerLookups == 0, @"a script that was not written is not run");

    // No ScriptRunner inside TeXShop (a damaged copy): nothing is run and the script is removed.
    [GlobalData sharedGlobalData].tempAppleScriptPath = [folder stringByAppendingString:@"/"];
    runner = nil;
    NSUInteger beforeMissing = Contents(folder).count;
    RunScript(@"-- macro");
    Check(Contents(folder).count == beforeMissing, @"the script is removed when there is no ScriptRunner");

    // A ScriptRunner that cannot be started.
    [GlobalData sharedGlobalData].tempAppleScriptPath = [folder stringByAppendingString:@"/"];
    NSString *notRunnable = [base stringByAppendingPathComponent:@"ScriptRunner"];
    [@"" writeToFile:notRunnable atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    runner = notRunnable;
    NSUInteger before = Contents(folder).count;
    @try {
        RunScript(@"-- macro");
        Check(Contents(folder).count == before, @"the script of a ScriptRunner that cannot be started is removed");
    } @catch (NSException *exception) {
        Check(NO, [@"a ScriptRunner that cannot be started raises: " stringByAppendingString:exception.reason ?: @""]);
    }
    if (!failures) puts("PASS: AppleScript macros are written in the temporary folder and run only when they can be");
    return failures ? 1 : 0;
} }
'''

def run(program):
    with tempfile.TemporaryDirectory(prefix='texshop-applescript-macro-') as temp:
        t = Path(temp)
        (t/'probe.m').write_text(program)
        build = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fmodules', '-w', '-framework', 'Cocoa', str(t/'probe.m'),
                                '-o', str(t/'probe')], capture_output=True, text=True)
        if build.returncode:
            return 2, build.stderr
        work = t/'Work'; work.mkdir()
        home = t/'Home'; (home/'Library/Preferences').mkdir(parents=True)
        result = subprocess.run([str(t/'probe'), str(work)], capture_output=True, text=True, timeout=60,
                                env={**os.environ, 'CFFIXED_USER_HOME': str(home), 'TMPDIR': str(t)})
        return result.returncode, result.stdout + result.stderr

program = PROGRAM.replace('STATEMENTS', statements)
verify_embedded(program, fragments)
if '--mutations' in sys.argv:
    for name, (old, new) in MUTATIONS.items():
        if old not in program:
            raise SystemExit(f'FAIL: mutation {name} does not apply')
        code, output = run(program.replace(old, new, 1))
        if code == 0:
            raise SystemExit(f'FAIL: mutation {name} was not detected')
        print('detected mutation', name)
code, output = run(program)
print(output.strip())
raise SystemExit(code)
