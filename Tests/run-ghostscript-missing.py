#!/usr/bin/env python3
"""Ghostscript is optional: what needs it says so, and the wrappers find it in the PATH.

Compiles the checks in Sources/Typesetting/TSGhostscriptCheck.inc, runs the ps2pdf and
version wrappers with stand-in programs and a PATH without Ghostscript, and checks that
opening .ps, .eps and .dvi files and Via DVI typesetting look for Ghostscript first.
No window, panel or alert is shown, and no TeX or Ghostscript is needed.
"""
from pathlib import Path
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
mutation = sys.argv[1] if len(sys.argv) > 1 else ''

PROBE = r'''
#import <Foundation/Foundation.h>
#include "TSGhostscriptCheck.inc"
static void check(BOOL ok, NSString *message) { if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); } }
int main(int argc, char **argv) { @autoreleasepool {
    NSString *base = @(argv[1]);
    NSString *with = [base stringByAppendingPathComponent:@"with"], *plain = [base stringByAppendingPathComponent:@"plain"];
    NSString *notExecutable = [base stringByAppendingPathComponent:@"noexec"], *folder = [base stringByAppendingPathComponent:@"folder"];
    check(TSGhostscriptFoundInPath([@[plain, with] componentsJoinedByString:@":"]), @"gs in a later PATH folder is found");
    check(!TSGhostscriptFoundInPath([@[plain, notExecutable, folder, @""] componentsJoinedByString:@":"]), @"no executable gs file is not Ghostscript");
    check(!TSGhostscriptFoundInPath(nil) && !TSGhostscriptFoundInPath(@""), @"no PATH has no Ghostscript");
    NSArray *transparency = @[@"latex", @"--maxpfb", @"--distilleropts", @"\"-dALLOWPSTRANSPARENCY\""];
    for (NSString *program in @[@"simpdftex", @"/Library/TeX/texbin/simpdftex", @"/Applications/TeXShop.app/Contents/Resources/Shellscripts/altpdflatex", @"altpdftex"])
        check([TSGhostscriptFoldersForCommand(program, transparency) isEqual:@[@"/usr/local/bin"]], [NSString stringWithFormat:@"%@ runs ps2pdf after adding /usr/local/bin", program]);
    for (NSString *program in @[@"ptex2pdf", @"/Users/x/Library/TeXShop/bin/uplatex2pdf", @"pdflatex", @"lualatex", @"xelatex", @"latexmk", @"", @"simpdftex-old"])
        check(TSGhostscriptFoldersForCommand(program, @[@"-l", @"--distiller", @"ps2pdf"]) == nil, [NSString stringWithFormat:@"%@ does not run Ghostscript", program]);
    NSDictionary *cases = @{
        @[@"--distiller-path", @"/no-gs"]: @[@"/no-gs"],
        @[@"--distiller-path=/opt/gs/bin"]: @[@"/opt/gs/bin"],
        @[@"--distiller-path", @""]: @[],
        @[@"--distiller", @"ps2pdf"]: @[@"/usr/local/bin"],
        @[@"--distiller", @"ps2pdf13"]: @[@"/usr/local/bin"],
        @[@"--distiller=/usr/local/bin/ps2pdf13"]: @[@"/usr/local/bin", @"/usr/local/bin"],
        @[@"--distiller", @"/opt/local/bin/ps2pdf -dCompatibilityLevel=1.5"]: @[@"/usr/local/bin", @"/opt/local/bin"],
        @[@"--distiller-filter", @"gs -q -dNOPAUSE"]: @[@"/usr/local/bin"],
        @[@"--distiller-path", @"/a", @"--distiller", @"ps2pdf"]: @[@"/a"],
    };
    for (NSArray *arguments in cases)
        check([TSGhostscriptFoldersForCommand(@"altpdflatex", [@[@"latex"] arrayByAddingObjectsFromArray:arguments]) isEqual:cases[arguments]],
              [NSString stringWithFormat:@"%@ runs Ghostscript with the folders %@", [arguments componentsJoinedByString:@" "], cases[arguments]]);
    for (NSArray *arguments in @[@[@"--distiller", @"/usr/local/alternate/bin/pstill"], @[@"--distiller=pstill"], @[@"--distiller-filter", @"u-psbuild"],
                                 @[@"--distiller-path", @"/a", @"--distiller", @"other"]])
        check(TSGhostscriptFoldersForCommand(@"simpdftex", [@[@"latex"] arrayByAddingObjectsFromArray:arguments]) == nil,
              [NSString stringWithFormat:@"%@ uses another converter", [arguments componentsJoinedByString:@" "]]);
    check(TSGhostscriptFoldersForCommand(@"simpdftex", @[@"latex", @"--distilleropts", @"--distiller"]) != nil, @"the value of --distilleropts is not an option");
    check(TSGhostscriptFoldersForCommand(nil, nil) == nil, @"no command does not run Ghostscript");
    // simpdftex can make the PDF with dvipdfm or dvipdfmx instead; the last choice counts.
    NSDictionary *modes = @{
        @[@"--mode", @"dvipdfmx"]: @NO, @[@"--mode", @"dvipdfm"]: @NO, @[@"--dpx"]: @NO, @[@"--dpm"]: @NO,
        @[@"--mode", @"dvips"]: @YES, @[@"--dpx", @"--mode", @"dvips"]: @YES, @[@"--mode", @"dvipdfmx", @"--mode", @"dvips"]: @YES,
        @[@"--mode", @"dvips", @"--dpx"]: @NO, @[@"--mode", @"unknown"]: @YES, @[@"--dpx", @"--distiller", @"ps2pdf"]: @NO,
    };
    for (NSArray *arguments in modes) {
        NSArray *full = [[@[@"latex"] arrayByAddingObjectsFromArray:arguments] arrayByAddingObject:@"a.tex"];
        check((TSGhostscriptFoldersForCommand(@"/Library/TeX/texbin/simpdftex", full) != nil) == [modes[arguments] boolValue],
              [NSString stringWithFormat:@"simpdftex %@ %@ Ghostscript", [arguments componentsJoinedByString:@" "], [modes[arguments] boolValue] ? @"needs" : @"does not need"]);
    }
    check(TSGhostscriptFoldersForCommand(@"altpdflatex", @[@"--dpx", @"--mode", @"dvipdfmx"]) != nil, @"altpdflatex has no dvipdfmx mode");
    puts("PASS checks");
}}
'''

with tempfile.TemporaryDirectory(prefix='texshop-ghostscript-') as temp:
    temp = Path(temp)
    for name in ('with', 'plain', 'noexec', 'folder/gs'):
        (temp / name).mkdir(parents=True)
    (temp / 'with/gs').write_text('#!/bin/sh\n'); (temp / 'with/gs').chmod(0o755)
    (temp / 'noexec/gs').write_text('#!/bin/sh\n'); (temp / 'noexec/gs').chmod(0o644)
    include = temp / 'include'; include.mkdir()
    check_source = (ROOT / 'Sources/Typesetting/TSGhostscriptCheck.inc').read_text()
    if mutation == 'any-gs-file':
        check_source = check_source.replace('&& !isFolder &&\n            [[NSFileManager defaultManager] isExecutableFileAtPath:program]', '')
    if mutation == 'any-distiller-option':
        check_source = check_source.replace('if (![options containsObject:name])\n            continue;', 'if ([name hasPrefix:@"--distiller"]) return nil;\n        if (![options containsObject:name])\n            continue;')
    if mutation == 'ignore-mode':
        check_source = check_source.replace('if (![dviProgram isEqualToString:@"dvips"])', 'if (dviProgram == nil)')
    if mutation == 'mode-for-all':
        check_source = check_source.replace('BOOL simpdftex = [program.lastPathComponent isEqualToString:@"simpdftex"];', 'BOOL simpdftex = YES;')
    if mutation == 'path-not-searched':
        check_source = check_source.replace('[folders addObject:distillerPath];', ';')
    (include / 'TSGhostscriptCheck.inc').write_text(check_source)
    (temp / 'probe.m').write_text(PROBE)
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-I', str(include), '-framework', 'Foundation',
                    str(temp / 'probe.m'), '-o', str(temp / 'probe')], check=True)
    subprocess.run([str(temp / 'probe'), str(temp)], check=True)

    # The wrappers, with stand-in gs and ps2pdf that record how they were called.
    scripts = ROOT / 'Resources/Shellscripts'
    log = temp / 'log'
    def standin(folder, version):
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'gs').write_text(f'#!/bin/sh\necho {version}\n')
        (folder / 'ps2pdf').write_text(f'#!/bin/sh\necho "ps2pdf $*" >> "{log}"\n')
        for program in ('gs', 'ps2pdf'):
            (folder / program).chmod(0o755)
    standin(temp / 'onpath', '10.05.1')
    standin(temp / 'setting-old', '9.50')
    work = temp / 'work'; work.mkdir(); (work / 'a.ps').write_text('%!PS\n')
    def run(script, *arguments, path):
        log.unlink(missing_ok=True)
        environment = {'PATH': path, 'HOME': str(temp)}
        result = subprocess.run(['/bin/tcsh', '-f', str(scripts / script), *arguments], cwd=work, env=environment,
                                capture_output=True, text=True, timeout=30)
        return result.returncode, log.read_text() if log.exists() else '', result.stdout + result.stderr
    system = '/usr/bin:/bin'
    transparency = 'ps2pdftransparencywrap'
    if mutation == 'transparency-needs-setting':
        source = (scripts / transparency).read_text().replace('endif\n\nset filename', 'else\n    exit 0\nendif\n\nset filename', 1)
        transparency = temp / 'mutated-transparency'; transparency.write_text(source); transparency.chmod(0o755)
    code, calls, _ = run(transparency, 'Ghostscript', str(temp / 'empty'), 'a.ps', path=f'{temp / "onpath"}:{system}')
    assert code == 0 and calls.strip() == 'ps2pdf -dALLOWPSTRANSPARENCY a.ps', (code, calls, 'Ghostscript in the PATH is used when the setting has none')
    code, calls, _ = run(transparency, 'Ghostscript', str(temp / 'setting-old'), 'a.ps', path=system)
    assert code == 0 and calls.strip() == 'ps2pdf a.ps', (code, calls, 'Ghostscript before 9.51 gets no -dALLOWPSTRANSPARENCY')
    code, calls, output = run(transparency, 'Ghostscript', str(temp / 'empty'), 'a.ps', path=system)
    assert code != 0 and 'ps2pdf' in output and 'not found' in output, (code, output, 'without Ghostscript the conversion fails visibly')
    code, calls, output = run('ps2pdfwrap', 'Ghostscript', str(temp / 'empty'), 'a.ps', path=system)
    assert code != 0 and 'not found' in output, (code, output, 'ps2pdfwrap without Ghostscript fails visibly')
    for path, setting, expected, reason in [(f'{temp / "onpath"}:{system}', temp / 'empty', 0, 'new Ghostscript in the PATH'),
                                            (system, temp / 'setting-old', 1, 'Ghostscript 9.50 in the setting'),
                                            (system, temp / 'empty', 1, 'no Ghostscript')]:
        code, _, _ = run('gstestwrap', str(setting), path=path)
        assert code == expected, (code, reason, 'gstestwrap')
    print('PASS wrappers: Ghostscript from the setting or the PATH, version 9.51 for transparency, visible failure without it')

# Where Ghostscript is needed, TeXShop looks for it first.
jobs = (ROOT / 'Sources/Typesetting/TSDocument-Jobs.m').read_text(encoding='latin1')
if mutation == 'no-eps-check':
    jobs = jobs.replace('''			if (! [self ghostscriptIsAvailableAlsoIn: nil]) {
				self.texTask = nil;
				return;
			}
			enginePath = [[NSBundle mainBundle] pathForResource:@"epstopdfwrap"''', '''			enginePath = [[NSBundle mainBundle] pathForResource:@"epstopdfwrap"''')
assert '#include "TSGhostscriptCheck.inc"' in jobs
convert = jobs[jobs.index('- (void) convertDocument'):jobs.index('- (void) saveFinished:')]
for kind, marker in [('dvi', 'isEqualToString:@"dvi"]) {\n\t\t\t[self testGSCommandKey];'), ('ps', 'isEqualToString:@"ps"]) {'), ('eps', 'isEqualToString:@"eps"]) {')]:
    branch = convert[convert.index(marker):]
    branch = branch[:branch.index('} else if') if kind != 'eps' else branch.index('\n\t\t}')]
    guard = 'TSGhostscriptFoldersForCommand(enginePath, args);\n\t\t\tif ((ghostscriptFolders != nil) && ! [self ghostscriptIsAvailableAlsoIn: ghostscriptFolders])' if kind == 'dvi' else '! [self ghostscriptIsAvailableAlsoIn: nil]'
    assert guard in branch and 'self.texTask = nil;\n\t\t\t\treturn;' in branch, (kind, 'opening the file looks for Ghostscript first')
typeset = jobs[jobs.index('- (void) saveFinished:'):]
start = typeset.index('[self startTask: self.texTask running: enginePath')
assert '(theScript == kTypesetViaGhostScript) ? TSGhostscriptFoldersForCommand(enginePath, args) : nil;\n\t\t\tif ((ghostscriptFolders != nil) && ! [self ghostscriptIsAvailableAlsoIn: ghostscriptFolders])' in typeset[start - 400:start], 'Via DVI typesetting looks for Ghostscript first, also where the command looks'
available = jobs[jobs.index('- (BOOL)ghostscriptIsAvailableAlsoIn:'):]
available = available[:available.index('\n}\n')]
assert 'path = [[[folders componentsJoinedByString:@":"] stringByAppendingString:@":"] stringByAppendingString:path];' in available and 'TSGhostscriptFoundInPath(path)' in available and \
       'NSLocalizedString(@"Ghostscript was not found. Install Ghostscript, then choose Detect Paths in Settings > Typesetting."' in available
assert '[args addObject:tetexBinPath ?: @""];' in jobs, 'no Ghostscript path does not raise in TestGSVersion'

key = 'Ghostscript was not found. Install Ghostscript, then choose Detect Paths in Settings > Typesetting.'
for language in ('en', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pt-PT', 'pt', 'ro', 'zh_CN'):
    table = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(ROOT / f'Resources/Interfaces/{language}.lproj/Localizable.strings')]))
    value = table.get(key, '')
    assert 'Ghostscript' in value and (language == 'en' or value != key), (language, 'the message is translated')
print('PASS: .ps, .eps and .dvi files and Via DVI typesetting look for Ghostscript first; the message exists in 12 languages')
