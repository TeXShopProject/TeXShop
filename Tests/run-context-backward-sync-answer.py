#!/usr/bin/env python3
"""Only mtxrun's answer to a backward sync takes TeXShop to a place (Sources/Sync/TSDocument-SyncConTeXt.m).

mtx-synctex --report --console prints "file" line tolerance, the file name quoted as Lua's %q does (\\" \\\\ \\ddd). An error message that quotes a file, a line number of 0,
text around the answer on the same line and an empty answer give no place, so that no document is opened and nothing
is sent to an external editor. Both the sync in TeXShop and the one to an external editor read the answer this way.
--mutations checks that the strictness is needed."""
import os, shutil, subprocess, sys, tempfile
from pathlib import Path
from production_fragments import method as production_method, verify_embedded
from source_tree import include_args

root = Path(__file__).resolve().parents[1]
source = (root/'Sources/Sync/TSDocument-SyncConTeXt.m').read_text()
unquote = production_method(source, 'static NSString *TSLuaUnquoted(NSString *quoted)')
place = production_method(source, 'static BOOL TSContextSyncPlace(NSString *output, NSString **fileName, NSInteger *line)')
fragments = [('complete function TSLuaUnquoted', source, unquote), ('complete function TSContextSyncPlace', source, place)]
call = '    if (! TSContextSyncPlace(outputString, &foundFileName, &theLine))\n        return NO;\n'
assert source.count(call) == 2, 'both backward syncs read the answer with TSContextSyncPlace'
assert 'componentsSeparatedByCharactersInSet: mySet' not in source, 'no other reading of the answer'

MUTATIONS = {
    'line-zero': ('([1-9][0-9]{0,8})', '([0-9]{1,9})'),
    'anywhere': ('@"(?:^|\\\\n)[ \\\\t]*\\"', '@"\\"'),
    'no-tolerance': ('(?:[ \\\\t]+-?[0-9]+)?', ''),
    'quote-unescaped': ('if (c != \'\\\\\') { [name', 'if (YES) { [name'),
    'escaped-break-ends-name': ('\\\\\\\\[\\\\s\\\\S]', '\\\\\\\\.'),
    'no-byte-escapes': ('if (c >= \'0\' && c <= \'9\') {', 'if (NO) {'),
}

PROGRAM = r'''
#import <Foundation/Foundation.h>
PLACE
static int failures;
static void Check(BOOL ok, NSString *what) { if (!ok) { failures++; printf("FAIL: %s\n", what.UTF8String); } }
int main(int argc, char **argv) { @autoreleasepool {
    NSString *file = nil; NSInteger line = 0;
    // The answers of mtx-synctex (%q %i %i), alone or after other output.
    Check(TSContextSyncPlace(@"\"chapter one.tex\" 54 0\n", &file, &line) && [file isEqual:@"chapter one.tex"] && line == 54, @"an answer with the tolerance");
    file = nil; line = 0;
    Check(TSContextSyncPlace(@"mtx-synctex     | loading\n\"/Users/a/b.tex\" 7 2\n", &file, &line) && [file isEqual:@"/Users/a/b.tex"] && line == 7, @"an answer after a report line");
    file = nil; line = 0;
    Check(TSContextSyncPlace(@"\"a.tex\" 12", &file, &line) && [file isEqual:@"a.tex"] && line == 12, @"an answer without the tolerance");
    // File names that Lua's %q escapes (here as TeX Live's texlua writes them, or as given when it is missing).
    NSArray *names = @[@"say \"hi\".tex", @"back\\slash.tex", @"car\rriage.tex", @"日本語 名前.tex", @"line\nbreak.tex", @"sep\u2028arator.tex"];
    NSArray *answers = [[NSString stringWithContentsOfFile:@(argv[1]) encoding:NSUTF8StringEncoding error:NULL] componentsSeparatedByString:@"\x1e"];
    for (NSUInteger i = 0; i < names.count; i++) {
        file = nil; line = 0;
        NSString *answer = i < answers.count ? answers[i] : @"";
        Check(TSContextSyncPlace(answer, &file, &line) && [file isEqual:names[i]] && line == 54,
              [NSString stringWithFormat:@"a quoted name comes back: %@ -> %@", answer, file]);
    }
    for (NSString *output in @[@"\"bad\\q.tex\" 3 0\n", @"\"a\\999.tex\" 3 0\n", @"\"ends\\\" 3 0\n",@"", @"mtxrun: command not found\n", @"error: file \"a.synctex\" not found 3\n",
                               @"invalid synctex log file \"a.synctex\"\n", @"\"a.tex\" 0 0\n", @"\"a.tex\" -3 0\n",
                               @"\"\" 4 0\n", @"\"a.tex\"\n", @"\"a.tex\" 99999999999 0\n", @"x \"a.tex\" 5 0\n"]) {
        file = nil; line = -1;
        Check(!TSContextSyncPlace(output, &file, &line) && file == nil && line == -1, [@"no place for: " stringByAppendingString:output]);
    }
    if (!failures) puts("PASS: only mtxrun's answer to a backward sync takes TeXShop to a place");
    return failures ? 1 : 0;
} }
'''

NAMES = ['say "hi".tex', 'back\\slash.tex', 'car\rriage.tex', '日本語 名前.tex', 'line\nbreak.tex', 'sep\u2028arator.tex']
def lua_quoted(name):
    """Lua 5.3's %q, for when texlua is missing."""
    out = bytearray(b'"')
    for b in name.encode('utf-8'):
        if b in b'"\\\n': out += b'\\' + bytes([b])
        elif b < 32 or b == 127: out += b'\\%d' % b
        else: out.append(b)
    return (out + b'"').decode('utf-8')
def answers(t):
    texlua = shutil.which('texlua') or '/Applications/TeXLive/2026/bin/universal-darwin/texlua'
    if os.path.exists(texlua):
        script = t/'q.lua'
        script.write_text(''.join('io.write(string.format("%%q %%i %%i\\n", %s, 54, 0), "\\30")\n' % lua_literal(n) for n in NAMES))
        result = subprocess.run([texlua, str(script)], capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout
    return ''.join(lua_quoted(n) + ' 54 0\n\x1e' for n in NAMES)
def lua_literal(name):
    return '"' + ''.join('\\%d' % b for b in name.encode('utf-8')) + '"'

def run(program):
    with tempfile.TemporaryDirectory(prefix='texshop-context-sync-') as temp:
        t = Path(temp)
        (t/'answers.txt').write_text(answers(t))
        (t/'probe.m').write_text(program)
        build = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-unused-function', *include_args(root),
                                '-framework', 'Foundation', str(t/'probe.m'), '-o', str(t/'probe')], capture_output=True, text=True)
        if build.returncode:
            return 2, build.stderr
        result = subprocess.run([str(t/'probe'), str(t/'answers.txt')], capture_output=True, text=True, timeout=60)
        return result.returncode, result.stdout + result.stderr

program = PROGRAM.replace('PLACE', unquote + '\n' + place)
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
