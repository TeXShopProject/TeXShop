#!/usr/bin/env python3
"""The TeX scanner of syntax coloring works with Foundation only.

The scanners (layer 1 of Sources/Syntax) are compiled and linked with Foundation
alone, without AppKit, and give tokens in the order they are found: a range that
is only left out of spell checking has no role, a key of expl3 and its property
follow each other, and a yen sign starts commands when it is the TeX character.
The options are a value: a mutable copy does not change the original. The ranges
to scan again are whole lines. (What the tokens look like in the source is
checked by run-syntax-coloring-golden.py.)
"""
from pathlib import Path
import subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[1]
SYNTAX = ROOT / 'Sources/Syntax'
LAYER1 = ['TSSyntaxScanner.m', 'TSSyntaxTeXOptions.m', 'TSSyntaxTeXScanner.m', 'TSSyntaxXMLScanning.m']
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
sources = {name: (SYNTAX / name).read_text(encoding='utf-8') for name in LAYER1}
if mutation == 'copy-shares-values':
    sources['TSSyntaxTeXOptions.m'] = sources['TSSyntaxTeXOptions.m'].replace(
        '    TSMutableSyntaxTeXOptions *copy = [TSMutableSyntaxTeXOptions new];\n    [self copyValuesTo:copy];\n    return copy;',
        '    return (id)self;')
elif mutation == 'yen-ignored':
    sources['TSSyntaxTeXScanner.m'] = sources['TSSyntaxTeXScanner.m'].replace('else if (c == texCharacter) {', "else if (c == '\\\\' && texCharacter) {")
elif mutation:
    sys.exit('unknown mutation ' + mutation)

PROGRAM = r'''
#import <Foundation/Foundation.h>
#import "TSSyntaxTeXScanner.h"
static int failures;
static void Check(BOOL ok, const char *name) { if (!ok) { printf("FAIL: %s\n", name); failures++; } }
static NSString *Tokens(TSSyntaxTeXOptions *options, NSString *text)
{
    NSMutableArray *tokens = [NSMutableArray array];
    TSSyntaxTeXScanner *scanner = [[TSSyntaxTeXScanner alloc] initWithOptions:options];
    NSRange lines = [scanner lineAlignedRangeForEditedRange:NSMakeRange(0, text.length) inString:text];
    [scanner enumerateTokensInString:text range:lines usingBlock:^(NSRange range, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
        [tokens addObject:[NSString stringWithFormat:@"%@:%ld%@", [text substringWithRange:NSIntersectionRange(range, NSMakeRange(0, text.length))],
                           (long)role, (flags & TSSyntaxTokenFlagsNoSpellCheck) ? @"!" : @""]];
    }];
    return [tokens componentsJoinedByString:@" "];
}
int main(void) { @autoreleasepool {
    TSMutableSyntaxTeXOptions *options = [TSMutableSyntaxTeXOptions new];
    NSString *plain = Tokens(options, @"\\emph{a} % b\n");
    Check([plain isEqual:[NSString stringWithFormat:@"\\emph:%ld {:%ld }:%ld %% b:%ld", (long)TSSyntaxRoleCommand,
           (long)TSSyntaxRoleBracketCurly, (long)TSSyntaxRoleBracketCurly, (long)TSSyntaxRoleComment]], "a command, braces and a comment");
    options.excludesCommandsFromSpelling = YES;
    options.excludesCommentsFromSpelling = YES;
    NSString *unspelled = Tokens(options, @"\\emph % b\n");
    Check([unspelled isEqual:[NSString stringWithFormat:@"\\emph:%ld \\emph:%ld! %% b:%ld %% b:%ld!", (long)TSSyntaxRoleCommand,
           (long)TSSyntaxRoleNone, (long)TSSyntaxRoleComment, (long)TSSyntaxRoleNone]], "ranges left out of spell checking have no role");

    TSMutableSyntaxTeXOptions *expl = [TSMutableSyntaxTeXOptions new];
    expl.colorsExpl3 = YES;
    NSString *key = Tokens(expl, @"name .tl_set:N = \\l_my_tl\n");
    Check([key hasPrefix:[NSString stringWithFormat:@"name:%ld name:%ld! .tl_set:N:%ld .tl_set:N:%ld! \\l_my_tl:%ld \\l_my_tl:%ld!",
           (long)TSSyntaxRoleExplKey, (long)TSSyntaxRoleNone, (long)TSSyntaxRoleExplKeyArgument, (long)TSSyntaxRoleNone,
           (long)TSSyntaxRoleExplVariable, (long)TSSyntaxRoleNone]], "an expl3 key, its property and a variable");

    TSMutableSyntaxTeXOptions *yen = [TSMutableSyntaxTeXOptions new];
    yen.texCharacter = 0x00A5;
    Check([Tokens(yen, @"\u00a5section \\x\n") isEqual:[NSString stringWithFormat:@"\u00a5section:%ld", (long)TSSyntaxRoleCommand]],
          "a yen sign starts a command, and a backslash then does not");

    TSSyntaxTeXOptions *frozen = [options copy];
    TSMutableSyntaxTeXOptions *changed = [frozen mutableCopy];
    changed.excludesCommandsFromSpelling = NO;
    changed.texCharacter = 0x00A5;
    Check(frozen.excludesCommandsFromSpelling && frozen.texCharacter == '\\', "a mutable copy leaves the original alone");
    Check([frozen copy] == frozen, "an immutable copy is the same object");
    TSSyntaxTeXScanner *scanner = [[TSSyntaxTeXScanner alloc] initWithOptions:changed];
    changed.texCharacter = '\\';
    Check(scanner.options.texCharacter == 0x00A5, "the scanner keeps its own copy of the options");

    NSString *text = @"first line\nsecond line\nthird";
    NSRange lines = [scanner lineAlignedRangeForEditedRange:NSMakeRange(14, 2) inString:text];
    Check(NSEqualRanges(lines, NSMakeRange(11, 12)), "an edit is scanned again as whole lines");
    if (failures) return 1;
    printf("PASS: the TeX scanner works with Foundation only, in order, with yen signs, expl3 and spelling ranges\n");
} return 0; }
'''

with tempfile.TemporaryDirectory(prefix='texshop-tex-scanner-') as tmp:
    tmp = Path(tmp)
    for name in ('TSSyntaxRole.h', 'TSSyntaxScanner.h', 'TSSyntaxTeXOptions.h', 'TSSyntaxTeXScanner.h', 'TSSyntaxXMLScanning.h'):
        (tmp / name).write_text((SYNTAX / name).read_text(encoding='utf-8'), encoding='utf-8')
    for name, source in sources.items():
        (tmp / name).write_text(source, encoding='utf-8')
    (tmp / 'probe.m').write_text(PROGRAM, encoding='utf-8')
    # Foundation only: AppKit is neither included nor linked.
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Foundation', '-I', str(tmp),
                    str(tmp / 'probe.m'), *[str(tmp / name) for name in LAYER1], '-o', str(tmp / 'probe')], check=True)
    linked = subprocess.run(['otool', '-L', str(tmp / 'probe')], capture_output=True, text=True).stdout
    assert 'AppKit' not in linked, linked
    result = subprocess.run([str(tmp / 'probe')], capture_output=True, text=True)
print(result.stdout, end='')
if mutation:
    if result.returncode == 0:
        sys.exit(f'FAIL: mutation {mutation} was not detected')
    print(f'PASS: detected mutation {mutation}')
elif result.returncode:
    sys.exit('FAIL')
