#!/usr/bin/env python3
"""Users of earlier versions get html.engine among the active engines, once.

Help > HTML Commands opens Help.html, which is typeset with html.engine. Earlier versions kept that
engine among the inactive ones, so TSAppDelegate copies the bundled html.engine into
~/Library/TeXShop/Engines when it updates a library last updated by a version before 6.00 beta-10.
A copy the user removes later stays removed (later versions do not copy it again), and an engine of
the user's own with that name is kept. The block of TSAppDelegate.m runs in a probe against a
temporary folder; no window is shown. With --mutation NAME the harness runs mutated sources and must
fail; --mutations runs them all."""
from pathlib import Path
import os
import re
import stat
import html.parser
import subprocess
import sys
import tempfile
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
MUTATIONS = {
    # Every update copies it again, so a removed engine comes back.
    'every-update': ('if (needsUpdating && TSLibraryNeedsUpdating(libraryVersion, @"6.00 beta-10")) {', 'if (needsUpdating) {'),
    # The user's own html.engine is replaced.
    'overwrite': ('if (bundledEngine && ![fileManager fileExistsAtPath:htmlEngine] && [fileManager fileExistsAtPath:bundledEngine])',
                  'if (bundledEngine && [fileManager fileExistsAtPath:bundledEngine] && ([fileManager removeItemAtPath:htmlEngine error:NULL] || YES))'),
    # Nothing is copied.
    'never': ('            [fileManager copyItemAtPath:bundledEngine toPath:htmlEngine error:NULL];', '            ;'),
    # The previous version is read after it was overwritten with the current one.
    # The page of Inactive links to history.html again, which a case-sensitive volume does not find.
    'lowercase-link': ('Resources/TeXShop/HTML/Inactive/InitialVersion/Help.html', 'HREF="History.html"', 'HREF="history.html"'),
    'version-late': ('	NSString *libraryVersion = TSLibraryVersionInFolder(NewPath);\n', '	NSString *libraryVersion = currentVersion;\n'),
}

PROBE = r'''
#import <Foundation/Foundation.h>
#import "TSLibraryVersion.h"
static NSString *EnginePath;
int main(int argc, const char **argv)
{
    @autoreleasepool {
        // argv: library folder (holds Engines), bundle resources, library version or "", application version
        NSString *NewPath = [@(argv[1]) stringByAppendingPathComponent:@"New"];
        EnginePath = [@(argv[1]) stringByAppendingPathComponent:@"Engines"];
        NSString *resources = @(argv[2]);
        if (strlen(argv[3]))
            [@(argv[3]) writeToFile:[NewPath stringByAppendingPathComponent:@".Version"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSString *currentVersion = @(argv[4]);
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL needsUpdating;
%VERSION%
%BLOCK%
    }
    return 0;
}
'''


def blocks(text):
    version = re.search(r'^\tNSString \*libraryVersion = .*\n\tneedsUpdating = .*\n', text, re.M)
    block = re.search(r'^    // Help > HTML Commands typesets with html\.engine\..*?^    }\n', text, re.M | re.S)
    return (version.group(0) if version else None), (block.group(0) if block else None)


class Tags(html.parser.HTMLParser):
    def __init__(self):
        super().__init__()
        self.tags = []

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, attrs))


def check_help_page(overrides=None):
    """Help.html of HTML Commands, and the copy in HTML/Inactive/InitialVersion that TeXShop also
    gives users, no longer point to the removed Help > TeXShop Demos movies or embed a video, are not
    signed as Richard Koch's page, link only to files beside them, and show img with real
    attributes (alt text, no misspelled ones a browser drops)."""
    for folder in ('Resources/TeXShop/HTML', 'Resources/TeXShop/HTML/Inactive/InitialVersion'):
        name = folder + '/Help.html'
        page = (overrides or {}).get(name) or (root / name).read_text(encoding='utf-8')
        for word in ('TeXShop Demos', '<video', '<iframe', 'Getting Started.mp4', 'University of Oregon'):
            if word in page:
                return name + ' still contains ' + word
        if '% !TEX TS-program = html' not in page:
            return name + ' must still be typeset with html.engine'
        # Compare with the names in the folder, letter case too: a case-sensitive volume finds nothing else.
        names = {p.name for p in (root / folder).iterdir()}
        for link in re.findall(r'(?i)(?:href|src)="([^":]+)"', page):
            if link not in names:
                return name + ' links to a missing file: ' + link
        parser = Tags()
        parser.feed(page)
        images = [dict(attrs) for tag, attrs in parser.tags if tag == 'img']
        if not images:
            return name + ' must show how to insert an image'
        for image in images:
            known = {'src', 'alt', 'width', 'height'}
            if not image.get('alt') or set(image) - known:
                return name + ': img needs alt text and only real attributes: ' + repr(image)
    return None


def run(mutation=None):
    overrides = {}
    if mutation and len(MUTATIONS[mutation]) == 3:
        path, old, new = MUTATIONS[mutation]
        page = (root / path).read_text(encoding='utf-8')
        if page.count(old) != 1:
            return 'mutation target must be unique: ' + mutation
        overrides[path] = page.replace(old, new)
        mutation = None
    problem = check_help_page(overrides)
    if problem:
        return problem
    text = source_file(root, 'TSAppDelegate.m').read_text(encoding='utf-8')
    if mutation:
        old, new = MUTATIONS[mutation]
        if text.count(old) != 1:
            return 'mutation target must be unique: ' + mutation
        text = text.replace(old, new)
    version, block = blocks(text)
    if version is None or block is None:
        return 'TSAppDelegate must read the library version before updating and place html.engine'
    # The block comes before the HTML folder and after the version is known.
    if text.index(version) > text.index(block):
        return 'html.engine must be placed after the library version is read'
    bundled = root / 'Resources/TeXShop/Engines/html.engine'
    if not bundled.exists() or not os.access(bundled, os.X_OK):
        return 'the bundled html.engine must exist among the active engines and be executable'
    with tempfile.TemporaryDirectory(prefix='texshop-html-engine-') as tmp:
        tmp = Path(tmp)
        probe = tmp / 'probe.m'
        probe.write_text(PROBE.replace('%VERSION%', version).replace('%BLOCK%', block.replace('[[NSBundle mainBundle] resourcePath]', 'resources')))
        exe = tmp / 'probe'
        built = subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Foundation', *include_args(root),
                                str(probe), str(source_file(root, 'TSLibraryVersion.m')), '-o', str(exe)],
                               capture_output=True, text=True)
        if built.returncode != 0:
            return 'probe did not compile: ' + built.stderr[-1500:]
        resources = root / 'Resources'
        env = {**os.environ, 'HOME': str(tmp), 'CFFIXED_USER_HOME': str(tmp), 'TMPDIR': str(tmp) + '/'}

        def launch(name, library_version, app_version, own=None):
            library = tmp / name
            (library / 'Engines').mkdir(parents=True)
            (library / 'New').mkdir()
            if own is not None:
                (library / 'Engines/html.engine').write_text(own)
            subprocess.run([str(exe), str(library), str(resources), library_version, app_version],
                           check=True, timeout=60, env=env)
            return library / 'Engines/html.engine'

        cases = [
            ('5.59', '6.00 beta-10', True, 'a 5.59 library gets html.engine'),
            ('6.00 beta-8', '6.00 beta-10', True, 'a 6.00 beta-8 library gets html.engine'),
            ('6.00b9.1', '6.00b10.1', True, 'a company 6.00b9.1 library gets html.engine'),
            ('', '6.00 beta-10', True, 'a library without a version file gets html.engine'),
            ('6.00 beta-10', '6.00 beta-11', False, 'a library updated by 6.00 beta-10 or later does not get it again'),
            ('6.00', '6.00.1', False, 'a 6.00 library does not get it again'),
            ('6.00 beta-10', '6.00 beta-10', False, 'no update, no copy'),
        ]
        for number, (library_version, app_version, placed, label) in enumerate(cases):
            engine = launch('case%d' % number, library_version, app_version)
            if engine.exists() != placed:
                return label
            if placed and (engine.read_bytes() != bundled.read_bytes() or not os.stat(engine).st_mode & stat.S_IXUSR):
                return label + ': a copy of the bundled, executable engine'
        engine = launch('own', '5.59', '6.00 beta-10', own='#!/bin/sh\n# mine\n')
        if engine.read_text() != '#!/bin/sh\n# mine\n':
            return 'an html.engine of the user is kept'
    return None


def main():
    args = sys.argv[1:]
    if args == ['--mutations']:
        ok = True
        for name in MUTATIONS:
            problem = run(name)
            print(('CAUGHT ' if problem else 'SURVIVED ') + name + (': ' + problem if problem else ''))
            ok = ok and bool(problem)
        sys.exit(0 if ok else 1)
    problem = run(args[1] if args[:1] == ['--mutation'] else None)
    if problem:
        sys.exit('FAIL: ' + problem)
    print('PASS: html.engine is placed once for libraries of versions before 6.00 beta-10; later updates and own engines are left alone')


if __name__ == '__main__':
    main()
