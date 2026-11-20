#!/usr/bin/env python3
"""TSRootFileResolver reads "% !TEX root" and "%SourceDoc" exactly as -checkMasterFile:forTask: and -decodeFile:
always have. The old code is kept below, word for word, as the reference; a table of quirks and thousands of generated
sources must give the same specifier and the same path. With --mutations, three broken copies must be caught."""
from pathlib import Path
import os, subprocess, sys, tempfile

root = Path(__file__).resolve().parents[1]
resolver_m = (root / 'Sources/Document/TSRootFileResolver.m').read_text(encoding='utf-8')
resolver_h = root / 'Sources/Document'

# The parsing part of -checkMasterFile:forTask: and the body of -decodeFile:homePath:job: as they were in TeXShop 6.00
# beta 1 (master e4e1dee8), with only `self` calls replaced by parameters.
REFERENCE = r'''
static NSString *RefSpecifier(NSString *theSource, BOOL useOld, int *kind)
{
	NSRange aRange, bRange, myRange, theRange, sourcedocRange, newSourceDocRange;
	NSString *testString, *sourcedocString;
	NSUInteger length; BOOL done; NSInteger linesTested, offset; NSUInteger start, end, irrelevant;
	*kind = 0;
	if (theSource == nil) return nil;
	length = [theSource length]; done = NO; linesTested = 0;
	myRange.location = 0; myRange.length = 1; sourcedocString = 0;
	while ((myRange.location < length) && (!done) && (linesTested < 20)) {
		[theSource getLineStart: &start end: &end contentsEnd: &irrelevant forRange: myRange];
		myRange.location = end; myRange.length = 1; linesTested++;
		theRange.location = start; theRange.length = (end - start);
		testString = [theSource substringWithRange: theRange];
		sourcedocRange = [testString rangeOfString:@"%!TEX root ="]; offset = 12;
		if (sourcedocRange.location == NSNotFound) { sourcedocRange = [testString rangeOfString:@"% !TEX root ="]; offset = 13; }
		if (sourcedocRange.location != NSNotFound) {
			newSourceDocRange.location = sourcedocRange.location + offset;
			newSourceDocRange.length = [testString length] - newSourceDocRange.location;
			if (newSourceDocRange.length > 0) {
				sourcedocString = [[testString substringWithRange: newSourceDocRange]
						stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
				if ([sourcedocString length] > 0) { done = YES; *kind = 1; }
			}
		}
	}
	if (!done && useOld) {
		aRange = [theSource rangeOfString:@"%SourceDoc "];
		if (aRange.location != NSNotFound) {
			bRange = [theSource lineRangeForRange:aRange];
			if (bRange.length > 12 && aRange.location == bRange.location) {
				sourcedocString = [theSource substringWithRange:NSMakeRange(bRange.location+11,bRange.length-12)];
				if ([sourcedocString length] > 0) { done = YES; *kind = 2; }
			}
		}
	}
	return done ? sourcedocString : nil;
}

static NSString *RefDecode(NSString *relFile, NSString *home, NSString *jobname, NSString *searchString)
{
	NSString *saveName; NSMutableString *saveTemp; unichar firstChar; NSRange aRange;
	relFile = [relFile stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	firstChar = [relFile characterAtIndex:0];
	if (firstChar == '~') saveName = [relFile stringByExpandingTildeInPath];
	else if (firstChar == '/') saveName = relFile;
	else if (firstChar == '.') {
		while ([relFile hasPrefix:@"../"]) { home = [home stringByDeletingLastPathComponent]; relFile = [relFile substringFromIndex:3]; }
		saveName = [NSString stringWithFormat:@"%@/%@",home,relFile];
	} else saveName = [NSString stringWithFormat:@"%@/%@",home,relFile];
	NSString *aName = [saveName stringByResolvingSymlinksInPath]; saveName = aName;
	aRange = [saveName rangeOfString:searchString options:NSLiteralSearch];
	if(aRange.location == NSNotFound) return saveName;
	saveTemp = [NSMutableString stringWithString:saveName];
	[saveTemp replaceOccurrencesOfString:searchString withString:jobname options:NSLiteralSearch range:NSMakeRange(0,[saveName length])];
	return [NSString stringWithString:saveTemp];
}
'''

PROGRAM = r'''
#import <Foundation/Foundation.h>
#import "TSRootFileResolver.h"
REFERENCE
static int failures = 0;
static void Fail(NSString *what) { if (failures < 25) printf("FAIL: %s\n", what.UTF8String); failures++; }
static NSString *Show(NSString *s) { return s ? [NSString stringWithFormat:@"'%@'", [[s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"]] : @"nil"; }
static void Compare(NSString *src, BOOL useOld, NSString *label) {
    int k = 0; NSString *ref = RefSpecifier(src, useOld, &k);
    TSRootFileSpecifier *s = [TSRootFileResolver specifierInSource:src allowingSourceDoc:useOld];
    BOOL same = (ref == nil && s == nil) || (ref && s && [ref isEqualToString:s.value] && k == (int)s.kind);
    if (!same) Fail([NSString stringWithFormat:@"%@ old=%@/%d new=%@/%ld src=%@", label, Show(ref), k, Show(s.value), (long)s.kind, Show(src)]);
}
static void Expect(NSString *src, BOOL useOld, NSString *value, NSInteger kind, NSString *label) {
    TSRootFileSpecifier *s = [TSRootFileResolver specifierInSource:src allowingSourceDoc:useOld];
    BOOL ok = value ? (s && [s.value isEqualToString:value] && s.kind == kind) : (s == nil);
    if (!ok) Fail([NSString stringWithFormat:@"%@: expected %@ got %@", label, Show(value), Show(s.value)]);
    Compare(src, useOld, label);
}
int main(void) { @autoreleasepool {
    // The quirks the specification names, with their expected values.
    Expect(@"% !TEX root = main.tex\n", NO, @"main.tex", 1, @"basic");
    Expect(@"%!TEX root = main.tex\n", NO, @"main.tex", 1, @"no space before !");
    Expect(@"%!TEX root =main.tex\n", NO, @"main.tex", 1, @"no space after =");
    Expect(@"% !TEX root=main.tex\n", NO, nil, 0, @"no space before =");
    Expect(@"% !TeX root = main.tex\n", NO, nil, 0, @"TeX is case sensitive");
    Expect(@"%  !TEX root = main.tex\n", NO, nil, 0, @"two spaces after %");
    Expect(@"text % !TEX root = main.tex\n", NO, @"main.tex", 1, @"anywhere on the line");
    Expect(@"% !TEX root =   \n% !TEX root = second.tex\n", NO, @"second.tex", 1, @"empty value is skipped");
    Expect(@"% !TEX root = a.tex % !TEX root = b.tex\n", NO, @"a.tex % !TEX root = b.tex", 1, @"first marker on the line");
    Expect(@"% !TEX root = a.tex\n%!TEX root = b.tex\n", NO, @"a.tex", 1, @"first line wins");
    Expect(@"% !TEX root = b.tex %!TEX root = a.tex\n", NO, @"a.tex", 1, @"%!TEX looked for first on the line");
    NSMutableString *twenty = [NSMutableString string]; for (int i = 0; i < 19; i++) [twenty appendString:@"x\n"];
    Expect([twenty stringByAppendingString:@"% !TEX root = r.tex\n"], NO, @"r.tex", 1, @"20th line");
    Expect([twenty stringByAppendingString:@"x\n% !TEX root = r.tex\n"], NO, nil, 0, @"21st line");
    Expect([twenty stringByAppendingString:@"\n"], NO, nil, 0, @"empty lines count");
    Expect(@"a\r\nb\r% !TEX root = r.tex\r\n", NO, @"r.tex", 1, @"CRLF and CR");
    Expect(@"a\u2028b\u2029% !TEX root = r.tex", NO, @"r.tex", 1, @"Unicode line separators, no final newline");
    Expect(@"%SourceDoc root.tex\n", YES, @"root.tex", 2, @"SourceDoc");
    Expect(@"%SourceDoc root.tex\n", NO, nil, 0, @"SourceDoc needs the old setting");
    Expect(@"%SourceDoc root.tex", YES, @"root.te", 2, @"SourceDoc last line loses a character");
    Expect(@"x %SourceDoc root.tex\n%SourceDoc other.tex\n", YES, nil, 0, @"SourceDoc only the first, only at line start");
    NSMutableString *deep = [NSMutableString string]; for (int i = 0; i < 22; i++) [deep appendString:@"x\n"];
    Expect([deep stringByAppendingString:@"%SourceDoc root.tex\n"], YES, @"root.tex", 2, @"SourceDoc past line 20");
    Expect(@"% !TEX root = a.tex\n%SourceDoc b.tex\n", YES, @"a.tex", 1, @"TEX root before SourceDoc");
    Expect(@"%SourceDoc \n", YES, nil, 0, @"SourceDoc too short");
    Expect(@"", NO, nil, 0, @"empty source");
    if ([TSRootFileResolver specifierInSource:nil allowingSourceDoc:YES] != nil) Fail(@"nil source");

    // Generated sources: pieces that touch every branch, joined with every kind of line break.
    NSArray *pieces = @[@"% !TEX root = a.tex", @"%!TEX root = b.tex", @"%!TEX root =", @"% !TEX root =  ", @"% !TEX root=c.tex",
        @"x % !TEX root = d.tex y", @"%SourceDoc e.tex", @"%SourceDoc ", @"  %SourceDoc f.tex", @"text", @"", @"% !TeX root = g.tex",
        @"%!TEX root = \t", @"日本語 % !TEX root = 章.tex", @"%SourceDoc 日本.tex"];
    NSArray *breaks = @[@"\n", @"\r", @"\r\n", @"\u2028", @"\u2029", [NSString stringWithFormat:@"%C", (unichar)0x85]];
    srandom(45); NSUInteger compared = 0;
    for (int n = 0; n < 6000; n++) {
        NSMutableString *src = [NSMutableString string];
        long lines = random() % 26;
        for (long i = 0; i < lines; i++) {
            [src appendString:pieces[random() % pieces.count]];
            if (i + 1 < lines || random() % 2) [src appendString:breaks[random() % breaks.count]];
        }
        Compare(src, NO, @"generated"); Compare(src, YES, @"generated old"); compared += 2;
    }

    // Paths: the same as -decodeFile:homePath:job:, on real folders with a symbolic link.
    NSString *tmp = [[NSFileManager.defaultManager.temporaryDirectory.path stringByAppendingPathComponent:@"root-resolver"] stringByResolvingSymlinksInPath];
    [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
    NSString *proj = [tmp stringByAppendingPathComponent:@"proj"], *ch = [proj stringByAppendingPathComponent:@"chapters"];
    [NSFileManager.defaultManager createDirectoryAtPath:ch withIntermediateDirectories:YES attributes:nil error:nil];
    [@"" writeToFile:[proj stringByAppendingPathComponent:@"main.tex"] atomically:NO encoding:NSUTF8StringEncoding error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[proj stringByAppendingPathComponent:@"link.tex"] withDestinationPath:@"main.tex" error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[tmp stringByAppendingPathComponent:@"alias"] withDestinationPath:proj error:nil];
    NSArray *names = @[@"../main.tex", @"main.tex", @"./main.tex", @"../../proj/main.tex", @" ../link.tex ", @"../\\jobname.tex",
        @"../¥jobname.tex", @"/tmp/x.tex", @"~/x.tex", @"..\\x", @"../../alias/main.tex", @".hidden.tex", @"../a b.tex"];
    for (NSString *token in @[@"\\jobname", @"¥jobname"])
        for (NSString *name in names) {
            NSString *old = RefDecode(name, ch, @"one", token);
            NSString *new = [TSRootFileResolver pathForName:name homePath:ch jobName:@"one" jobNameToken:token];
            if (![old isEqualToString:new]) Fail([NSString stringWithFormat:@"path %@ old=%@ new=%@", name, old, new]);
        }
    NSString *spec; TSRootFileSpecifier *found;
    spec = [TSRootFileResolver rootPathInSource:@"% !TEX root = ../link.tex\n" documentPath:[ch stringByAppendingPathComponent:@"one.tex"]
                              allowingSourceDoc:NO jobNameToken:@"\\jobname" specifier:&found];
    if (![spec isEqualToString:[proj stringByAppendingPathComponent:@"main.tex"]] || found.kind != 1) Fail([@"rootPath " stringByAppendingString:Show(spec)]);
    // A name of only spaces names no file (the old code raised); an untitled document has no job name, so
    // \jobname stays as it is.
    @try {
        if (![[TSRootFileResolver pathForName:@"  " homePath:ch jobName:@"one" jobNameToken:@"\\jobname"] isEqualToString:@""]) Fail(@"empty name did not give an empty path");
        NSString *untitled = [TSRootFileResolver pathForName:@"\\jobname-main.tex" homePath:ch jobName:nil jobNameToken:@"\\jobname"];
        if (![untitled hasSuffix:@"\\jobname-main.tex"]) Fail([@"an untitled document's \\jobname was replaced: " stringByAppendingString:Show(untitled)]);
    } @catch (NSException *e) { Fail([@"a name without a file or job raised: " stringByAppendingString:e.reason ?: @""]); }
    [NSFileManager.defaultManager removeItemAtPath:tmp error:nil];
    printf("compared %lu generated sources\n", (unsigned long)compared);
    return failures ? 1 : 0;
} }
'''

MUTATIONS = {
    'twenty-one': ('linesTested < 20', 'linesTested < 21'),
    'empty-ends': ('        if (value.length > 0)\n            return [[TSRootFileSpecifier alloc] initWithKind:TSRootFileSpecifierKindTeXRoot value:value];',
                   '        return value.length > 0 ? [[TSRootFileSpecifier alloc] initWithKind:TSRootFileSpecifierKindTeXRoot value:value] : nil;'),
    'sourcedoc-anywhere': ('if (line.length <= 12 || marker.location != line.location)', 'if (line.length <= 12)'),
}

def run(source_text):
    with tempfile.TemporaryDirectory(prefix='texshop-root-resolver-') as tmp:
        tmp = Path(tmp)
        (tmp / 'TSRootFileResolver.m').write_text(source_text, encoding='utf-8')
        (tmp / 'test.m').write_text(PROGRAM.replace('REFERENCE', REFERENCE), encoding='utf-8')
        exe = tmp / 'test'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wno-unused-variable', '-I', str(resolver_h),
                        '-framework', 'Foundation', str(tmp / 'test.m'), str(tmp / 'TSRootFileResolver.m'), '-o', str(exe)], check=True)
        env = dict(os.environ, TMPDIR=str(tmp) + '/')
        return subprocess.run([str(exe)], capture_output=True, text=True, timeout=300, env=env)

failures = []
src = (root / 'Sources/Document/TSDocument-RootFile.m').read_text(encoding='utf-8')
if '[TSRootFileResolver specifierInSource:theSource' not in src:
    failures.append('-checkMasterFile:forTask: does not read the root with TSRootFileResolver')
if 'return [TSRootFileResolver pathForName:relFile homePath:home jobName:jobname' not in src:
    failures.append('-decodeFile:homePath:job: does not use TSRootFileResolver')

if '--mutations' in sys.argv:
    for name, (a, b) in MUTATIONS.items():
        if a not in resolver_m:
            raise SystemExit('FAIL: mutation %s does not apply' % name)
        r = run(resolver_m.replace(a, b, 1))
        if r.returncode == 0:
            raise SystemExit('FAIL: mutation %s was not detected' % name)
        print('detected mutation', name)

r = run(resolver_m)
if r.stdout.strip(): print(r.stdout.strip())
if r.returncode: failures.append('the resolver differs from the old code')
for f in failures: print('FAIL:', f)
if failures: raise SystemExit(1)
print('PASS: "% !TEX root" and "%SourceDoc" are read and resolved exactly as before')
