#!/usr/bin/env python3
"""Only mtxrun's answer to a backward sync takes TeXShop to a place (Sources/Sync/TSDocument-SyncConTeXt.m).

mtx-synctex --report --console prints "file" line tolerance. An error message that quotes a file, a line number of 0,
text around the answer on the same line and an empty answer give no place, so that no document is opened and nothing
is sent to an external editor. Both the sync in TeXShop and the one to an external editor read the answer this way.
--mutations checks that the strictness is needed."""
import subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
source = (root/'Sources/Sync/TSDocument-SyncConTeXt.m').read_text()
place = production_method(source, 'static BOOL TSContextSyncPlace(NSString *output, NSString **fileName, NSInteger *line)')
fragments = [('complete function TSContextSyncPlace', source, place)]
call = '    if (! TSContextSyncPlace(outputString, &foundFileName, &theLine))\n        return NO;\n'
assert source.count(call) == 2, 'both backward syncs read the answer with TSContextSyncPlace'
assert 'componentsSeparatedByCharactersInSet: mySet' not in source, 'no other reading of the answer'

MUTATIONS = {
    'line-zero': ('([1-9][0-9]{0,8})', '([0-9]{1,9})'),
    'anywhere': ('@"^\\\\s*\\"', '@"\\"'),
    'no-tolerance': ('(\\\\s+-?[0-9]+)?', ''),
}

PROGRAM = r'''
#import <Foundation/Foundation.h>
PLACE
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); } }
int main(void) { @autoreleasepool {
    NSString *file = nil; NSInteger line = 0;
    // The answers of mtx-synctex (%q %i %i), alone or after other output.
    Check(TSContextSyncPlace(@"\"chapter one.tex\" 54 0\n", &file, &line) && [file isEqual:@"chapter one.tex"] && line == 54, @"an answer with the tolerance");
    file = nil; line = 0;
    Check(TSContextSyncPlace(@"mtx-synctex     | loading\n\"/Users/a/b.tex\" 7 2\n", &file, &line) && [file isEqual:@"/Users/a/b.tex"] && line == 7, @"an answer after a report line");
    file = nil; line = 0;
    Check(TSContextSyncPlace(@"\"a.tex\" 12", &file, &line) && [file isEqual:@"a.tex"] && line == 12, @"an answer without the tolerance");
    for (NSString *output in @[@"", @"mtxrun: command not found\n", @"error: file \"a.synctex\" not found 3\n",
                               @"invalid synctex log file \"a.synctex\"\n", @"\"a.tex\" 0 0\n", @"\"a.tex\" -3 0\n",
                               @"\"\" 4 0\n", @"\"a.tex\"\n", @"\"a.tex\" 99999999999 0\n", @"x \"a.tex\" 5 0\n"]) {
        file = nil; line = -1;
        Check(!TSContextSyncPlace(output, &file, &line) && file == nil && line == -1, [@"no place for: " stringByAppendingString:output]);
    }
    if (!failures) puts("PASS: only mtxrun's answer to a backward sync takes TeXShop to a place");
    return failures ? 1 : 0;
} }
'''

def run(program):
    with tempfile.TemporaryDirectory(prefix='texshop-context-sync-') as temp:
        t = Path(temp)
        (t/'probe.m').write_text(program)
        build = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-unused-function', *include_args(root),
                                '-framework', 'Foundation', str(t/'probe.m'), '-o', str(t/'probe')], capture_output=True, text=True)
        if build.returncode:
            return 2, build.stderr
        result = subprocess.run([str(t/'probe')], capture_output=True, text=True, timeout=60)
        return result.returncode, result.stdout + result.stderr

program = PROGRAM.replace('PLACE', place)
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
