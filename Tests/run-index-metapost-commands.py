#!/usr/bin/env python3
"""MakeIndex and MetaPost in the Typeset menu run the commands of Settings > Typesetting.

The launch code of -[TSDocument doJob:...] for the index (from Sources/Typesetting/TSDocument-Jobs.m) is compiled
with in-memory defaults and a stand-in for -startTask:, which records the program and the arguments instead of
running them. The MetaPost arguments made by the same code are passed to the shipped metapostwrap with a stand-in
MetaPost program that prints what it receives. The factory defaults, blank values, commands with options and the
values of every engine profile are checked; with TeX Live installed, the programs of the profiles must exist in it
and the Japanese ones run on a small index and figure. No window, panel or alert is shown, and the real
~/Library/Preferences is not used. Each production rule is then broken in turn, and the probe must notice."""
from pathlib import Path
import json, os, plistlib, shutil, subprocess, sys, tempfile
from source_tree import include_args, source_file

R = Path(__file__).resolve().parents[1]
FACTORY = R / 'Resources/Defaults/FactoryDefaults.plist'
WRAPPER = R / 'Resources/Shellscripts/metapostwrap'


def tex_bin():
    candidates = [Path('/Library/TeX/texbin')]
    for root in ('/Applications/TeXLive', '/usr/local/texlive'):
        for year in sorted(Path(root).glob('[0-9][0-9][0-9][0-9]'), reverse=True):
            candidates += [year / 'bin/universal-darwin', year / 'bin/arm64-darwin', year / 'bin/x86_64-darwin']
    return next((c for c in candidates if (c / 'mpost').exists() and (c / 'makeindex').exists()), None)


def between(text, start, end, include_end=False):
    a = text.index(start)
    b = text.index(end, a + len(start))
    return text[a:b + (len(end) if include_end else 0)]


def snippets(jobs):
    separate = between(jobs, '- (NSString *) separate: (NSString *)myEngine into:(NSMutableArray *)args', '\n}\n', True)
    index = between(jobs, 'else if (whichEngineLocal == IndexEngine) {', '} else if (whichEngineLocal >= UserEngine) {')
    index = index[len('else if (whichEngineLocal == IndexEngine) {'):]
    metapost = between(jobs, '            if (whichEngineLocal == MetapostEngine) {\n\t\t\t\tNSString* mpEngineString', '\t\t\t} else {')
    metapost = metapost[metapost.index('{') + 1:]
    tail = between(jobs, '\t\t\t[args addObject: [sourcePath lastPathComponent]];\n', '\n\t\t\t}\n', True)
    tail = tail[tail.index('\n') + 1:]
    return separate, index, metapost, tail


PROGRAM = r'''
#import <Cocoa/Cocoa.h>
#import "MemoryDefaults.h"
#import "globals.h"
#import "TSPreferenceProfile.h"
#undef SUD
static TSMemoryDefaults *memory;
#define SUD memory
@interface Doc : NSObject
@property (strong) NSTask *indexTask;
@property (copy) NSString *program;
@property (copy) NSArray *arguments;
@end
@implementation Doc
SEPARATE
- (BOOL) startTask: (NSTask*) task running: (NSString*) leafname withArgs: (NSMutableArray*) args inDirectoryContaining: (NSString*) sourcePath withEngine: (NSInteger)theEngine
{ self.program = leafname; self.arguments = args; return theEngine == IndexEngine; }
- (NSArray *)index:(NSString *)sourcePath
{
    NSMutableArray *args = [NSMutableArray array];
    NSInteger whichEngineLocal = IndexEngine;
    if (whichEngineLocal == IndexEngine) {
INDEX
    }
    return [@[self.program ?: @""] arrayByAddingObjectsFromArray:self.arguments ?: @[]];
}
- (NSArray *)metapost:(NSString *)sourcePath continuous:(BOOL)continuous
{
    NSMutableArray *args = [NSMutableArray array];
    NSInteger whichEngineLocal = MetapostEngine;
    NSString *enginePath = nil, *gsPath = nil;
    {
METAPOST
    }
    (void)enginePath;
    [args addObject: [sourcePath lastPathComponent]];
TAIL
    return args;
}
@end
int main(int argc, char **argv) { @autoreleasepool {
    memory = [TSMemoryDefaults new];
    [memory registerDefaults:[NSDictionary dictionaryWithContentsOfFile:@(argv[1])]];
    memory.values[@"TetexBinPath"] = @(argv[2]);
    memory.values[@"GSBinPath"] = @"/no-gs";
    NSArray *cases = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[3])] options:0 error:NULL];
    NSMutableArray *out = [NSMutableArray array];
    Doc *doc = [Doc new];
    for (NSDictionary *c in cases) {
        for (NSString *key in @[@"MakeIndexEngine", @"MetaPostEngine"]) {
            if (c[key] == nil) [memory.values removeObjectForKey:key]; else memory.values[key] = c[key];
        }
        doc.program = nil; doc.arguments = nil;
        [out addObject:@{@"index": [doc index:@"/tmp/some dir/my doc.tex"],
                         @"metapost": [doc metapost:@"/tmp/some dir/my fig.mp" continuous:[c[@"continuous"] boolValue]]}];
    }
    NSMutableArray *profiles = [NSMutableArray array];
    for (NSArray<NSNumber *> *section in TSEngineProfileMenuSections()) for (NSNumber *p in section) {
        NSDictionary *values = TSEngineProfileValues(p.integerValue, NO), *latexmk = TSEngineProfileValues(p.integerValue, YES);
        NSString *place = [latexmk[@"DefaultScript"] integerValue] == 100 ? @"LatexCommand" : @"LatexGSCommand";
        [profiles addObject:@{@"profile": p, @"MakeIndexEngine": values[@"MakeIndexEngine"] ?: @"", @"MetaPostEngine": values[@"MetaPostEngine"] ?: @"",
                              @"latexmk": latexmk[place] ?: @""}];
    }
    printf("%s", [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:@{@"cases": out, @"profiles": profiles} options:0 error:NULL] encoding:NSUTF8StringEncoding].UTF8String);
} return 0; }
'''

CASES = [
    {},                                                        # factory defaults
    {'MakeIndexEngine': '  ', 'MetaPostEngine': ''},           # blank values
    {'MakeIndexEngine': 'upmendex -s jpbase.ist', 'MetaPostEngine': 'upmpost -tex=uplatex', 'continuous': True},
    {'MakeIndexEngine': 'mendex', 'MetaPostEngine': 'pmpost "-jobname=a b"'},
    {'MakeIndexEngine': '/opt/bin/xindy', 'MetaPostEngine': '~/bin/mympost'},
]
EXPECTED_INDEX = [
    ['makeindex', 'my doc.idx'],
    ['makeindex', 'my doc.idx'],
    ['upmendex', '-s', 'jpbase.ist', 'my doc.idx'],
    ['mendex', 'my doc.idx'],
    ['/opt/bin/xindy', 'my doc.idx'],
]
# What the MetaPost program receives from metapostwrap, after the program's name.
EXPECTED_MP = [
    ('mpost', ['my fig.mp']),
    ('mpost', ['my fig.mp']),
    ('upmpost', ['-tex=uplatex', '--interaction=nonstopmode', 'my fig.mp']),
    ('pmpost', ['-jobname=a b', 'my fig.mp']),
    (None, None),
]
PROFILE_INDEX = {1: 'makeindex', 2: 'makeindex', 3: 'makeindex', 4: 'makeindex', 8: 'makeindex', 5: 'upmendex', 6: 'mendex', 7: 'upmendex'}
PROFILE_MP = {1: 'mpost', 2: 'mpost', 3: 'mpost', 4: 'mpost', 8: 'mpost', 5: 'mpost', 6: 'pmpost', 7: 'upmpost'}

MUTATIONS = {
    'index ignores the setting': ('TSDocument-Jobs.m', '[SUD stringForKey:MakeIndexEngineKey]', '@"makeindex"'),
    'blank index command runs nothing': ('TSDocument-Jobs.m', '(indexCommand.length > 0 ? indexCommand : @"makeindex")', 'indexCommand'),
    'index options dropped': ('TSDocument-Jobs.m', 'NSString *indexEngineString = [self separate:(indexCommand.length > 0 ? indexCommand : @"makeindex") into:args];',
                              'NSString *indexEngineString = [self separate:(indexCommand.length > 0 ? indexCommand : @"makeindex") into:[NSMutableArray array]];'),
    'MetaPost program not passed': ('TSDocument-Jobs.m', '\t\t\t\t[args addObject: [metapostProgram stringByExpandingTildeInPath]];\n', ''),
    'wrapper ignores the program': ('metapostwrap', '        set mpprogram = "$argv[5]"\n', ''),
    'wrapper drops the options': ('metapostwrap', '"$mpprogram" $mpoptions:q --interaction=nonstopmode', '"$mpprogram" --interaction=nonstopmode'),
    'pLaTeX profile with mpost': ('TSPreferenceProfile.m', '@"pbibtex", @"mendex", @"pmpost"]', '@"pbibtex", @"mendex", @"mpost"]'),
}


def run(t, jobs, wrapper, profile_source):
    separate, index, metapost, tail = snippets(jobs)
    (t / 'probe.m').write_text(PROGRAM.replace('SEPARATE', separate).replace('INDEX', index).replace('METAPOST', metapost).replace('TAIL', tail))
    (t / 'TSPreferenceProfile.m').write_text(profile_source)
    (t / 'cases.json').write_text(json.dumps(CASES))
    built = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-w', *include_args(R), '-I', str(R / 'Tests'), '-framework', 'Cocoa',
                            str(t / 'probe.m'), str(t / 'TSPreferenceProfile.m'), str(source_file(R, 'globals.m')), '-o', str(t / 'probe')],
                           capture_output=True, text=True)
    if built.returncode:
        return ['build: ' + built.stderr[-2000:]]
    fake = t / 'fake bin'
    fake.mkdir(exist_ok=True)
    for name in ('mpost', 'pmpost', 'upmpost'):
        (fake / name).write_text('#!/bin/sh\nprintf "%s\\n" "$(basename "$0")"\nfor a in "$@"; do printf "[%s]\\n" "$a"; done\n')
        (fake / name).chmod(0o755)
    (t / 'metapostwrap').write_text(wrapper)
    out = json.loads(subprocess.run([str(t / 'probe'), str(FACTORY), str(fake), str(t / 'cases.json')], capture_output=True, text=True, check=True).stdout)
    failures = []
    for i, (case, got) in enumerate(zip(CASES, out['cases'])):
        if got['index'] != EXPECTED_INDEX[i]:
            failures.append('index %d: %s' % (i, got['index']))
        mp = got['metapost']
        if mp[:3] != ['YES' if case.get('continuous') else 'NO', '/no-gs', str(fake) + '/'] or mp[3] != 'my fig.mp':
            failures.append('metapostwrap arguments 1-4 %d: %s' % (i, mp))
        program, rest = EXPECTED_MP[i]
        if program is None:
            if len(mp) != 5 or mp[4].startswith('~') or not mp[4].endswith('/bin/mympost'):
                failures.append('tilde not expanded: %s' % mp)
            continue
        work = t / ('work%d' % i)
        work.mkdir(exist_ok=True)
        ran = subprocess.run(['/bin/tcsh', '-f', str(t / 'metapostwrap'), *mp], cwd=work, capture_output=True, text=True,
                             env={'PATH': '/usr/bin:/bin', 'HOME': str(t)})
        lines = ran.stdout.splitlines()
        if not lines or lines[0] != program or [l[1:-1] for l in lines[1:]] != rest:
            failures.append('MetaPost %d ran: %s %s' % (i, lines, ran.stderr))
    for p in out['profiles']:
        n = p['profile']
        if p['MakeIndexEngine'] != PROFILE_INDEX[n] or p['MetaPostEngine'] != PROFILE_MP[n]:
            failures.append('profile %d: %s %s' % (n, p['MakeIndexEngine'], p['MetaPostEngine']))
        if PROFILE_INDEX[n] != 'makeindex' and ('$makeindex=q/%s/' % PROFILE_INDEX[n]) not in p['latexmk']:
            failures.append('profile %d latexmk index: %s' % (n, p['latexmk']))
        if PROFILE_INDEX[n] == 'makeindex' and '$makeindex' in p['latexmk']:
            failures.append('profile %d latexmk sets an index program: %s' % (n, p['latexmk']))
    return failures


def real_tex(t, tex):
    """The programs of the profiles exist, and the Japanese ones work through the shipped wrapper."""
    for name in sorted(set(PROFILE_INDEX.values()) | set(PROFILE_MP.values())):
        assert (tex / name).exists(), name + ' is not in ' + str(tex)
    work = t / 'real'
    work.mkdir()
    (work / 'doc.idx').write_text('\\indexentry{にほん@日本}{1}\n\\indexentry{apple}{2}\n', encoding='utf-8')
    for program in ('mendex', 'upmendex', 'makeindex'):
        ran = subprocess.run([str(tex / program), 'doc.idx'], cwd=work, capture_output=True, text=True, env={'PATH': str(tex) + ':/usr/bin:/bin', 'HOME': str(t)})
        assert ran.returncode == 0 and (work / 'doc.ind').exists(), (program, ran.stdout + ran.stderr)
        (work / 'doc.ind').unlink()
    (work / 'fig.mp').write_text('prologues:=3;\noutputtemplate:="%j-%c.mps";\nbeginfig(1);\ndraw (0,0)--(10,10);\n'
                                 'label(btex 日本語 etex, (5,5));\nendfig;\nend\n', encoding='utf-8')
    for program, font in (('pmpost', 'rml'), ('upmpost', 'uprml-h')):
        for f in work.glob('fig*'):
            if f.suffix != '.mp':
                f.unlink()
        ran = subprocess.run(['/bin/tcsh', '-f', str(WRAPPER), 'YES', '/no-gs', str(tex) + '/', 'fig.tex', program], cwd=work,
                             capture_output=True, text=True, env={'PATH': '/usr/bin:/bin', 'HOME': str(t)}, timeout=120)
        mps = work / 'fig-1.mps'
        assert ran.returncode == 0 and mps.exists() and font in mps.read_text(errors='replace'), (program, ran.stdout[-800:])
    print('OK TeX Live at %s: %s exist; mendex, upmendex and makeindex make an index; pmpost and upmpost set Japanese labels'
          % (tex, ', '.join(sorted(set(PROFILE_INDEX.values()) | set(PROFILE_MP.values())))))


with tempfile.TemporaryDirectory(prefix='texshop-index-metapost-') as temp:
    t = Path(temp)
    (t / 'Library').mkdir()
    jobs = source_file(R, 'TSDocument-Jobs.m').read_text(encoding='utf-8')
    wrapper = WRAPPER.read_text()
    profile = source_file(R, 'TSPreferenceProfile.m').read_text()
    factory = plistlib.loads(FACTORY.read_bytes())
    assert factory['MakeIndexEngine'] == 'makeindex' and factory['MetaPostEngine'] == 'mpost', 'factory defaults'
    failures = run(t, jobs, wrapper, profile)
    if failures:
        sys.exit('FAIL:\n' + '\n'.join(failures))
    print('PASS: MakeIndex and MetaPost run the commands of the settings (factory, blank, options, paths) and of the 8 profiles; '
          'metapostwrap keeps its first four arguments', flush=True)
    for name, (file, old, new) in MUTATIONS.items():
        sources = {'TSDocument-Jobs.m': jobs, 'metapostwrap': wrapper, 'TSPreferenceProfile.m': profile}
        assert sources[file].count(old) == 1, name
        sources[file] = sources[file].replace(old, new)
        sub = t / name.replace(' ', '-')
        sub.mkdir()
        assert run(sub, sources['TSDocument-Jobs.m'], sources['metapostwrap'], sources['TSPreferenceProfile.m']), name
        print('DETECTED', name, flush=True)
    (t / 'again').mkdir()
    assert not run(t / 'again', jobs, wrapper, profile)
    print('NORMAL CONTROL passes again')
    tex = tex_bin()
    if tex is None:
        print('SKIP: no TeX Live with mpost and makeindex')
    else:
        real_tex(t, tex)
