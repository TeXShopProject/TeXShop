#!/usr/bin/env python3
"""The contents of macros are split into tokens as they are run.

TSSyntaxMacroContentScanner and TSSyntaxAppleScriptScanner (layer 1 of
Sources/Syntax) are compiled with Foundation only. A TeX macro is scanned as the
source is, with its marks and the placeholders that a TeX macro replaces (#SEL#,
#PASTE#, the first #INS#); an AppleScript macro, which TSMacroContentKindForString
recognizes, gets comments (--, #, nested (* *)), strings, reserved words, numbers
and raw events, and the placeholders that AppleScript macros replace (#FILEPATH#
and the others), in comments and strings too. A placeholder is colored only where
the replacement would find it. Every AppleScript macro bundled with TeXShop is
scanned without an exception and starts with a comment.
"""
from pathlib import Path
import json, plistlib, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[1]
SYNTAX = ROOT / 'Sources/Syntax'
LAYER1 = [SYNTAX / n for n in ('TSSyntaxScanner.m', 'TSSyntaxTeXOptions.m', 'TSSyntaxTeXScanner.m', 'TSSyntaxXMLScanning.m',
                               'TSSyntaxAppleScriptScanner.m', 'TSSyntaxMacroContentScanner.m')] + [ROOT / 'Sources/Macros/TSMacroContentKind.m']
mutation = sys.argv[1] if len(sys.argv) > 1 else ''
sources = {p.name: p.read_text(encoding='utf-8') for p in LAYER1}
MUTATIONS = {
    # A # always starts an AppleScript comment, swallowing a placeholder at the start of a line.
    'hash-swallows-placeholder': ('TSSyntaxAppleScriptScanner.m', "NSUInteger placeholder = c == '#' ? [self placeholderLengthAtLocation:location inString:string] : 0;",
                                  "NSUInteger placeholder = 0;"),
    # Nested block comments end at the first *).
    'flat-block-comments': ('TSSyntaxAppleScriptScanner.m', 'depth--;\n                    location += 2;\n                    if (depth == 0)', 'depth = 0;\n                    location += 2;\n                    if (depth == 0)'),
    # Every #INS# is colored, although only the first is replaced.
    'every-insertion-point': ('TSSyntaxMacroContentScanner.m', 'if ([once containsObject:placeholder])\n                    break;', ''),
    # AppleScript macros get the placeholders of TeX macros.
    'wrong-placeholders': ('TSSyntaxMacroContentScanner.m', 'NSArray<NSString *> *placeholders = TSSyntaxMacroContentScanner.appleScriptPlaceholders;',
                           'NSArray<NSString *> *placeholders = TSSyntaxMacroContentScanner.teXPlaceholders;'),
}
if mutation:
    name, old, new = MUTATIONS[mutation]
    assert sources[name].count(old) == 1, mutation
    sources[name] = sources[name].replace(old, new)

# The bundled AppleScript macros.
macros = []
def walk(node):
    if isinstance(node, dict):
        content = node.get('content')
        if isinstance(content, str) and content.lower().startswith(('--applescript', '-- applescript')):
            macros.append(content)
        for child in node.get('submenu', []) or []:
            walk(child)
    elif isinstance(node, list):
        for child in node:
            walk(child)
for plist in sorted((ROOT / 'Resources/TeXShop/Macros').glob('Macros_*.plist')):
    walk(plistlib.loads(plist.read_bytes()))
assert len(macros) >= 40, len(macros)

PROGRAM = r'''
#import <Foundation/Foundation.h>
#import "TSSyntaxMacroContentScanner.h"
static int failures;
static void Check(BOOL ok, NSString *name) { if (!ok) { printf("FAIL: %s\n", name.UTF8String); failures++; } }
static NSString *Name(TSSyntaxRole role)
{
    switch (role) {
        case TSSyntaxRoleCommand: return @"command"; case TSSyntaxRoleComment: return @"comment";
        case TSSyntaxRoleMarker: return @"marker"; case TSSyntaxRoleBracketCurly: return @"curly";
        case TSSyntaxRoleBracketSquare: return @"square"; case TSSyntaxRoleBracketParen: return @"paren";
        case TSSyntaxRoleString: return @"string"; case TSSyntaxRoleKeyword: return @"keyword";
        case TSSyntaxRoleNumber: return @"number"; case TSSyntaxRoleRawEvent: return @"raw";
        case TSSyntaxRolePlaceholder: return @"placeholder"; case TSSyntaxRoleMark: return @"mark";
        case TSSyntaxRoleExplVariable: return @"variable";
        default: return [NSString stringWithFormat:@"role%ld", (long)role];
    }
}
// The tokens, as "text:role", in the order they come.
static NSString *Tokens(NSString *text)
{
    TSMutableSyntaxTeXOptions *options = [TSMutableSyntaxTeXOptions new];
    options.colorsExpl3 = YES;
    TSSyntaxMacroContentScanner *scanner = [[TSSyntaxMacroContentScanner alloc] initWithTeXOptions:options];
    NSRange all = [scanner lineAlignedRangeForEditedRange:NSMakeRange(text.length / 2, 0) inString:text];
    if (!NSEqualRanges(all, NSMakeRange(0, text.length))) return @"not the whole text";
    NSMutableArray *tokens = [NSMutableArray array];
    [scanner enumerateTokensInString:text range:all usingBlock:^(NSRange range, TSSyntaxRole role, TSSyntaxTokenFlags flags) {
        [tokens addObject:[NSString stringWithFormat:@"%@:%@", [text substringWithRange:range], Name(role)]];
    }];
    return [tokens componentsJoinedByString:@" "];
}
static void Expect(NSString *text, NSString *expected, NSString *name)
{
    NSString *tokens = Tokens(text);
    if (![tokens isEqual:expected]) printf("  got:      %s\n  expected: %s\n", tokens.UTF8String, expected.UTF8String);
    Check([tokens isEqual:expected], name);
}
int main(int argc, char **argv) { @autoreleasepool {
    // TeX macros: the rules of the source, then marks, then their placeholders.
    Expect(@"\\begin{#SEL#}#INS#\\end{x}#INS#",
           @"\\begin:command {:curly }:curly \\end:command {:curly }:curly #SEL#:placeholder #INS#:placeholder",
           @"a TeX macro colors #SEL# and the first #INS#, the one that is replaced");
    Expect(@"\\emph{•‹note›} • % #PASTE#\n#FILEPATH#",
           @"\\emph:command {:curly }:curly % #PASTE#:comment •‹note›:mark •:mark #PASTE#:placeholder",
           @"marks, and #PASTE# in a comment; #FILEPATH# is left alone in a TeX macro");
    Expect(@"#SEL#INS#", @"#SEL#:placeholder", @"#INS# sharing a # with #SEL# is gone once #SEL# is replaced");
    Expect(@"\\l_tmpa_tl", @"\\l_tmpa_tl:variable \\l_tmpa_tl:role-1", @"the TeX options apply");

    // AppleScript macros.
    Expect(@"--applescript direct\ntell application \"TeXShop\" to set x to 12.5e-3 -- done\n",
           @"--applescript direct:comment tell:keyword \"TeXShop\":string to:keyword set:keyword to:keyword 12.5e-3:number -- done:comment",
           @"the header, reserved words, a string, a number and a comment");
    Expect(@"-- applescript\n(* a (* nested *) comment *) END If\n#FILEPATH# & #NOTONE# x\n",
           @"-- applescript:comment (* a (* nested *) comment *):comment END:keyword If:keyword #NOTONE# x:comment #FILEPATH#:placeholder",
           @"nested block comments, reserved words in any case, a placeholder that is not a comment and one that is");
    Expect(@"--applescript\nset s to \"say \\\"hi\\\" #TEXPATH#\" & «event aevtodoc» & |set|\n#SEL# #INS#",
           @"--applescript:comment set:keyword to:keyword \"say \\\"hi\\\" #TEXPATH#\":string «event aevtodoc»:raw #SEL# #INS#:comment #TEXPATH#:placeholder",
           @"escaped quotes, a placeholder in a string, a raw event, a quoted identifier; #SEL# is not replaced in AppleScript");
    Expect(@"--applescript\n(* not closed\nset x to \"open", @"--applescript:comment (* not closed\nset x to \"open:comment",
           @"an unclosed comment runs to the end");
    Expect(@"--applescript\nset x to \"open\nline", @"--applescript:comment set:keyword to:keyword \"open\nline:string",
           @"an unclosed string runs to the end");

    // Every bundled AppleScript macro.
    NSArray *macros = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:NULL];
    NSUInteger checked = 0;
    for (NSString *macro in macros) {
        @try {
            NSString *tokens = Tokens(macro);
            NSString *firstLine = [macro substringToIndex:[macro lineRangeForRange:NSMakeRange(0, 0)].length];
            firstLine = [firstLine stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
            Check([tokens hasPrefix:[firstLine stringByAppendingString:@":comment"]], [@"the header is a comment: " stringByAppendingString:firstLine]);
            checked++;
        } @catch (NSException *exception) {
            Check(NO, [@"a bundled macro raised " stringByAppendingString:exception.reason]);
        }
    }
    if (failures) return 1;
    printf("PASS: macro contents are scanned as they are run, %lu bundled AppleScript macros included\n", (unsigned long)checked);
} return 0; }
'''

with tempfile.TemporaryDirectory(prefix='texshop-macro-scanners-') as tmp:
    tmp = Path(tmp)
    for header in list(SYNTAX.glob('*.h')) + [ROOT / 'Sources/Macros/TSMacroContentKind.h']:
        (tmp / header.name).write_text(header.read_text(encoding='utf-8'), encoding='utf-8')
    for name, source in sources.items():
        (tmp / name).write_text(source, encoding='utf-8')
    (tmp / 'probe.m').write_text(PROGRAM, encoding='utf-8')
    (tmp / 'macros.json').write_text(json.dumps(macros), encoding='utf-8')
    # Foundation only: AppKit is neither included nor linked.
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-framework', 'Foundation', '-I', str(tmp),
                    str(tmp / 'probe.m'), *[str(tmp / name) for name in sources], '-o', str(tmp / 'probe')], check=True)
    assert 'AppKit' not in subprocess.run(['otool', '-L', str(tmp / 'probe')], capture_output=True, text=True).stdout
    result = subprocess.run([str(tmp / 'probe'), str(tmp / 'macros.json')], capture_output=True, text=True, timeout=120)
print(result.stdout, end='')
if mutation:
    if result.returncode == 0:
        sys.exit(f'FAIL: mutation {mutation} was not detected')
    print(f'PASS: detected mutation {mutation}')
elif result.returncode:
    sys.exit('FAIL: ' + result.stderr)
