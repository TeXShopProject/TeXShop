#!/usr/bin/env python3
"""A new version of TeXShop updates unedited bundled macros that open the former web site.

The macro TeXShop home page of earlier versions opened Richard Koch's former web site. When
TeXShop is updated, a copy in ~/Library/TeXShop/Macros whose content is still exactly an earlier
bundled text opens https://texshop.app/. The same holds for the macros reworded in 6.00, taken
as earlier versions bundled them (Tests/Fixtures/FormerBundledMacros.plist): View TeX Live file
writes TeX Live with the space, and the ConTeXt macro teTeX/TeXLive home page becomes TeX Live home
page, which opens https://tug.org/texlive/; a copy the user renamed keeps its name and content. Program
no longer offers metafont and context, and Encoding offers DOSKorean. The macros renamed in 6.00 so that their names
say what they do (pdfselectc is Extract Pages from PDF…) take the new name when their content is still the bundled text
of 5.59 or of 6.00 RC and they still have the earlier name; the macros that run scripts in ~/Library/TeXShop/bin and the
line ending macros take the text that quotes file names for the shell, and Set Root File… the text that finds the
relative path without Perl. Their keys stay. A macro that was edited or
renamed by the user, and every other macro, keep their content, names, keys and order. Nothing is written when no macro changes, a symbolic link
stays a link, a binary file stays binary, and a file that cannot be read is left alone.
TSAppDelegate does this only when the bundled files of a new version are copied.

Runs in a temporary folder only. With --mutation NAME the harness runs mutated sources and must
fail; --mutations runs them all."""
import copy, os, plistlib, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
# The macros renamed in 6.00: (file, submenu), earlier name, current name.
RENAMED = {('Latex', ''): {'Program': 'Set Typesetting Program…', 'Encoding': 'Set Encoding…', 'Root': 'Set Root File…',
                          'Numbering': 'Page Number Correction', 'PreText Personal Mark': 'PreTeXt Tag Comment',
                          'Root (Short Version)': 'Root File Line', 'GetFontSet': 'Insert Font Set…', 'SaveFontSet': 'Save Font Set',
                          'TestFontSet': 'Test Font Set Sizes', 'Tabularize': 'Align Table Columns',
                          'Tabularize +space': 'Align Table Columns with Spaces'},
           ('Latex', 'Applescript'): {'Show files': 'Show Source and PDF in Finder',
                                      'Convert to MAC': 'Save Copy with Classic Mac Line Endings',
                                      'Convert to Unix': 'Save Copy with Unix Line Endings',
                                      'Convert to Windows': 'Save Copy with Windows Line Endings',
                                      'Bibliography': 'Run LaTeX, BibTeX, Then LaTeX Twice'},
           ('Latex', 'Claus Gerhardt Macros'): {'bibtexc': 'Run BibTeX, Then pdfLaTeX Twice',
                                                'bibtexcpl': 'Run pdfLaTeX, BibTeX, Then pdfLaTeX Twice',
                                                'mpostc': 'Run MetaPost, Then pdfLaTeX',
                                                'mpostcpl': 'Run pdfLaTeX, MetaPost, Then pdfLaTeX',
                                                'htlatexc': 'Make HTML with TeX4ht',
                                                'htlatexr': 'Make HTML with TeX4ht, Remaking Images',
                                                'altpdflatexc': 'Run LaTeX, dvips and ps2pdf',
                                                'pdflatexc': 'Run pdfLaTeX with Shell Escape',
                                                'pdfselectc': 'Extract Pages from PDF…',
                                                'openpdf': 'Open PDF',
                                                'latex-makeindex-mpost': 'Run pdfLaTeX, MakeIndex, MetaPost, Then pdfLaTeX'},
           ('Latex', 'Figures'): {'regular': 'figure'},
           ('Context', 'Applescript'): {'Show files': 'Show Source and PDF in Finder'}}
FORMER = ['https://pages.uoregon.edu/koch/texshop/texshop.html',
          'http://pages.uoregon.edu/koch/texshop/texshop.html',
          'http://www.uoregon.edu/~koch/texshop/texshop.html']
MUTATIONS = {
    # Any macro mentioning a former address is changed, edited ones too.
    'substring': ('    NSDictionary *target = [content isKindOfClass:[NSString class]] ? earlier[content] : nil;',
                  '    NSDictionary *target = [content isKindOfClass:[NSString class]] && [content containsString:@"uoregon"] ? earlier.allValues.firstObject : nil;'),
    # The reworded macros are not recognized.
    'reworded-ignored': ('    return macros;\n}', '    return @[];\n}'),
    # The renamed macros keep their earlier names.
    'renames-ignored': ('    return @{\n        @"Set Typesetting Program…": @"Program",', '    return @{}; (void)@{\n        @"Set Typesetting Program…": @"Program",'),
    # The macros of 5.59 that passed file names unquoted are not recognized.
    'unquoted-missing': ('        [macros addObject:@{@"name": name, @"changes": unquoted}];', '        ;'),
    # Set Root File… of 5.59 and 6.00 RC, which ran Perl, is not recognized.
    'root-perl-missing': ('        @{@"name": @"Set Root File…", @"changes": TSRootFileChanges()},', '        @{@"name": @"Set Root File…", @"changes": @[]},'),
    # The line ending macros of 5.59, which ran flip through tcsh, are not recognized.
    'flip-line-missing': (r'''[NSString stringWithFormat:@"\"/bin/tcsh -c '%@ \" & backupTexName & \"'\"", flip]''', '@"x"'),
    # A renamed macro takes its new name whatever name the user gave it.
    'rename-any-name': ('    if ([content isKindOfClass:[NSString class]] && formerName)\n        earlier[content] = @{@"content": content, @"name": name, @"formerName": formerName};',
                        '    if ([content isKindOfClass:[NSString class]] && formerName)\n        earlier[content] = @{@"content": content, @"name": name};'),
    # Program still offers metafont and context to earlier copies: they are not recognized.
    'program-list-missing': ('"\\"personallatex\\", \\"metapost\\", \\"metafont\\", \\"context\\"} & engines"', '"\\"personallatex\\", \\"metapost\\"} & engines"'),
    # Encoding without DOSKorean is not recognized.
    'encoding-list-missing': ('@[@"\\"MacKorean\\", \\"DOSKorean\\", \\"UTF-8 Unicode\\"", @"\\"MacKorean\\", \\"UTF-8 Unicode\\""]', '@[@"x", @"y"]'),
    # A copy the user renamed is updated too.
    'renamed-copy-updated': ('target[@"formerName"] == nil || [node[@"name"] isEqual:target[@"formerName"]]', 'YES'),
    # The renamed macro keeps its earlier name.
    'name-kept': ('            node[@"name"] = target[@"name"];', '            ;'),
    # The teTeX line of View TeX Live file is not part of the earlier text.
    'tetex-line-missing': ('                        @[@"any files in the TeX Live tree with", @"any files in the teTeX tree with"]]},', '                        ]},'),
    # The oldest address is not recognized.
    'oldest-missing': ('             @"http://www.uoregon.edu/~koch/texshop/texshop.html"];', '             ];'),
    # A symbolic link is replaced by a file.
    'link-replaced': ('[[NSURL fileURLWithPath:userPath] URLByResolvingSymlinksInPath]', '[NSURL fileURLWithPath:userPath]'),
    # The file is written even when nothing changed.
    'always-write': ('    if (count == 0)\n        return 0;\n    NSData *updated', '    NSData *updated'),
    # A binary file becomes XML.
    'format-lost': ('format:format options:0 error:NULL]', 'format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL]'),
    # The application never calls the update.
    'not-called': ('				TSUpdateUnchangedBundledMacros([[MacrosPath', '				if (0) TSUpdateUnchangedBundledMacros([[MacrosPath'),
    # Nothing is updated when the bundle has a resource folder.
    'no-resources': ('		if (resources) {', '		if (!resources) {'),
}


def find(node, name):
    for child in node.get('submenu', []):
        if child.get('name') == name:
            return child
        found = find(child, name)
        if found:
            return found


def macro_in(node, submenu, name):
    """The macro of this name in the submenu of this name (the top level for ''), not in a deeper one."""
    if submenu:
        node = next(child for child in node['submenu'] if child.get('name') == submenu and 'submenu' in child)
    found = [child for child in node['submenu'] if child.get('name') == name and 'submenu' not in child]
    return found[0] if len(found) == 1 else None


def all_contents(node):
    for child in node.get('submenu', []):
        if 'submenu' in child:
            yield from all_contents(child)
        elif child.get('content'):
            yield child['content']


def check_renamed(tmp, update, former):
    """Unedited copies of the renamed macros, as 5.59 and 6.00 RC bundled them, take the new names."""
    earlier_texts = {(entry['file'], entry['submenu'][0] if entry['submenu'] else '', entry['name']): entry['content']
                     for entry in former['Renamed']}
    earlier_texts[('Latex', '', 'Program')] = former['LatexProgram']['content']
    earlier_texts[('Latex', '', 'Encoding')] = former['LatexEncoding']['content']
    if set(earlier_texts) != {(kind, sub, old) for (kind, sub), names in RENAMED.items() for old in names}:
        return 'the fixture does not hold the earlier text of every renamed macro'
    for kind in ('Latex', 'Context'):
        bundled = root / 'Resources/TeXShop/Macros' / ('Macros_%s.plist' % kind)
        current = plistlib.loads(bundled.read_bytes())
        contents = list(all_contents(current))
        renamed = [(sub, old, new) for (k, sub), names in RENAMED.items() if k == kind for old, new in names.items()]
        for sub, old, new in renamed:
            macro = macro_in(current, sub, new)
            if macro is None or macro_in(current, sub, old) is not None:
                return '%s: %s is not renamed to %s' % (kind, old, new)
            if contents.count(macro['content']) != 1:
                return '%s: the text of %s is not the only one of its kind' % (kind, new)
        all_earlier = copy.deepcopy(current)
        for sub, old, new in renamed:
            # A copy of 5.59 and one of 6.00 RC (the current text), both under the earlier name, with a key the user gave it.
            for label, text in (('5.59', earlier_texts[(kind, sub, old)]), ('RC', macro_in(current, sub, new)['content'])):
                earlier = copy.deepcopy(current)
                macro_in(earlier, sub, new).update({'name': old, 'content': text, 'key': 'K+ControlKey'})
                user = tmp / ('%s-renamed.plist' % kind)
                user.write_bytes(plistlib.dumps(earlier))
                expected = copy.deepcopy(current)
                macro_in(expected, sub, new)['key'] = 'K+ControlKey'
                if update(user, bundled) != 1 or plistlib.loads(user.read_bytes()) != expected:
                    return '%s: the unedited %s copy of %s does not become %s with its key' % (kind, label, old, new)
            macro_in(all_earlier, sub, new).update({'name': old, 'content': earlier_texts[(kind, sub, old)]})
            # An edited copy, and a copy the user renamed, stay as they are.
            for label, change in (('edited', {'name': old, 'content': earlier_texts[(kind, sub, old)] + '\n'}),
                                  ('edited RC', {'name': old, 'content': macro_in(current, sub, new)['content'] + ' '}),
                                  ('renamed', {'name': 'My macro', 'content': earlier_texts[(kind, sub, old)]})):
                mine = copy.deepcopy(current)
                macro_in(mine, sub, new).update(change)
                user = tmp / ('%s-renamed-mine.plist' % kind)
                user.write_bytes(plistlib.dumps(mine))
                before = user.read_bytes()
                if update(user, bundled) != 0 or user.read_bytes() != before:
                    return '%s: a %s copy of %s was changed' % (kind, label, old)
        # A file of 5.59 with all of them unedited.
        user = tmp / ('%s-all-renamed.plist' % kind)
        user.write_bytes(plistlib.dumps(all_earlier))
        if update(user, bundled) != len(renamed) or plistlib.loads(user.read_bytes()) != current:
            return '%s: not every unedited renamed macro of 5.59 takes its new name' % kind
    return None


def check_delegate(text):
    start = text.index('if (! [fileManager fileExistsAtPath: [MacrosPath stringByStandardizingPath]] ) {')
    block = text[start:text.index('if (! [fileManager fileExistsAtPath: [MatrixPanelPath', start)]
    update = block[block.index('else if (needsUpdating) {'):]
    if 'if (resources) {' not in update:
        return 'TSAppDelegate must update the macros when the bundle has its resource folder'
    call = ('for (NSString *name in @[@"Macros_Latex.plist", @"Macros_Context.plist"])\n'
            '\t\t\t\tTSUpdateUnchangedBundledMacros([[MacrosPath stringByStandardizingPath] stringByAppendingPathComponent:name],')
    if call not in update:
        return 'TSAppDelegate must update unedited bundled macros of both files when a new version is copied'
    return None


def run(mutation=None):
    unit = source_file(root, 'TSBundledMacroUpdate.m')
    delegate = source_file(root, 'TSAppDelegate.m').read_text(encoding='utf-8')
    with tempfile.TemporaryDirectory(prefix='texshop-bundled-macro-update-') as tmp:
        tmp = Path(tmp)
        if mutation:
            old, new = MUTATIONS[mutation]
            text = unit.read_text(encoding='utf-8')
            if text.count(old) == 1:
                unit = tmp / 'TSBundledMacroUpdate.m'
                unit.write_text(text.replace(old, new), encoding='utf-8')
            else:
                assert delegate.count(old) == 1, 'mutation target must be unique: ' + mutation
                delegate = delegate.replace(old, new)
        problem = check_delegate(delegate)
        if problem:
            return problem
        exe = tmp / 'update'
        subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Foundation', *include_args(root),
                        str(root / 'Tests/BundledMacroUpdate.m'), str(unit), '-o', str(exe)], check=True)

        def update(user, bundled):
            return int(subprocess.run([str(exe), str(user), str(bundled)], capture_output=True, text=True,
                                      check=True, timeout=60).stdout)

        for kind in ('Latex', 'Context'):
            bundled = root / 'Resources/TeXShop/Macros' / ('Macros_%s.plist' % kind)
            current = plistlib.loads(bundled.read_bytes())
            text = find(current, 'TeXShop home page')['content']
            assert 'open location "https://texshop.app/"' in text, kind

            for number, address in enumerate(FORMER):
                # An unedited copy of an earlier version, among the other bundled macros.
                earlier = copy.deepcopy(current)
                find(earlier, 'TeXShop home page')['content'] = text.replace('https://texshop.app/', address)
                user = tmp / ('%s-%d.plist' % (kind, number))
                user.write_bytes(plistlib.dumps(earlier))
                if update(user, bundled) != 1:
                    return '%s: the unedited macro with %s is not updated' % (kind, address)
                after = plistlib.loads(user.read_bytes())
                if after != current:
                    return '%s: updating the macro with %s changed more than its address' % (kind, address)

            # An edited macro keeps its content, and the file is not written.
            edited = copy.deepcopy(current)
            mine = text.replace('https://texshop.app/', FORMER[0]) + '\n-- my note'
            find(edited, 'TeXShop home page')['content'] = mine
            find(edited, 'TeXShop home page')['name'] = 'Old home page'
            user = tmp / ('%s-edited.plist' % kind)
            user.write_bytes(plistlib.dumps(edited))
            before = user.read_bytes(); inode = os.stat(user).st_ino
            if update(user, bundled) != 0 or user.read_bytes() != before or os.stat(user).st_ino != inode:
                return '%s: an edited macro was changed or its file written' % kind

            # A file without the macro is not written.
            user = tmp / ('%s-current.plist' % kind)
            user.write_bytes(plistlib.dumps(current))
            before = user.read_bytes(); inode = os.stat(user).st_ino
            if update(user, bundled) != 0 or user.read_bytes() != before or os.stat(user).st_ino != inode:
                return '%s: a file without an earlier macro was written' % kind

            # A symbolic link stays a link, and the file it points to is updated.
            earlier = copy.deepcopy(current)
            find(earlier, 'TeXShop home page')['content'] = text.replace('https://texshop.app/', FORMER[0])
            target = tmp / ('elsewhere-%s.plist' % kind)
            target.write_bytes(plistlib.dumps(earlier))
            link = tmp / ('%s-link.plist' % kind)
            link.symlink_to(target)
            if update(link, bundled) != 1 or not link.is_symlink() or plistlib.loads(target.read_bytes()) != current:
                return '%s: a symbolic link is not kept' % kind

            # A binary file stays binary.
            user = tmp / ('%s-binary.plist' % kind)
            user.write_bytes(plistlib.dumps(earlier, fmt=plistlib.FMT_BINARY))
            if update(user, bundled) != 1 or not user.read_bytes().startswith(b'bplist'):
                return '%s: a binary file is not kept binary' % kind

            # A file that cannot be read is left alone.
            user = tmp / ('%s-broken.plist' % kind)
            user.write_bytes(b'not a property list')
            if update(user, bundled) != 0 or user.read_bytes() != b'not a property list':
                return '%s: a broken file was changed' % kind

        # The macros reworded in 6.00, as earlier versions bundled them.
        former = plistlib.loads((root / 'Tests/Fixtures/FormerBundledMacros.plist').read_bytes())
        for entry, kind, name, earlier_name in (('Latex', 'Latex', 'View TeX Live file', 'View TeX Live file'),
                                                ('Context', 'Context', 'TeX Live home page', 'teTeX/TeXLive home page'),
                                                ('LatexProgram', 'Latex', 'Set Typesetting Program…', 'Program'),
                                                ('LatexEncoding', 'Latex', 'Set Encoding…', 'Encoding')):
            bundled = root / 'Resources/TeXShop/Macros' / ('Macros_%s.plist' % kind)
            current = plistlib.loads(bundled.read_bytes())
            macro = find(current, name)
            if macro is None:
                return '%s: the bundled macro %s is missing' % (kind, name)
            if entry in ('Latex', 'Context') and ('TeXLive' in macro['content'] or 'teTeX' in macro['content'] + macro['name']):
                return '%s: %s still says TeXLive or teTeX' % (kind, name)
            if kind == 'Context' and 'open location "https://tug.org/texlive/"' not in macro['content']:
                return 'Context: TeX Live home page does not open https://tug.org/texlive/'
            if entry == 'LatexProgram' and ('"metafont"' in macro['content'] or '"context"' in macro['content']):
                return 'Latex: Program still offers metafont or context'
            if entry == 'LatexEncoding' and '"MacKorean", "DOSKorean", "UTF-8 Unicode"' not in macro['content']:
                return 'Latex: Encoding does not offer DOSKorean after MacKorean'
            if former[entry]['name'] != earlier_name or former[entry]['content'] == macro['content']:
                return '%s: the fixture does not hold the earlier %s' % (kind, earlier_name)
            # An unedited copy of the earlier macro, in its place among the other bundled macros.
            earlier = copy.deepcopy(current)
            find(earlier, name).update(copy.deepcopy(former[entry]))
            user = tmp / ('%s-reworded.plist' % kind)
            user.write_bytes(plistlib.dumps(earlier))
            if update(user, bundled) != 1 or plistlib.loads(user.read_bytes()) != current:
                return '%s: the unedited earlier %s is not updated to the current macro' % (kind, earlier_name)
            # An edited copy stays as it is; so does a copy the user renamed, where the macro itself was renamed.
            for label, change in (('edited', {'content': former[entry]['content'] + '\n-- mine'}),
                                  ('renamed', {'name': 'My TeX page'})):
                mine = copy.deepcopy(earlier)
                find(mine, earlier_name).update(change)
                user = tmp / ('%s-reworded-%s.plist' % (kind, label))
                user.write_bytes(plistlib.dumps(mine))
                before = user.read_bytes()
                expected = 1 if (label == 'renamed' and name == earlier_name) else 0
                if update(user, bundled) != expected:
                    return '%s: a %s copy of %s was handled wrongly' % (kind, label, earlier_name)
                after = plistlib.loads(user.read_bytes())
                if expected == 0 and user.read_bytes() != before:
                    return '%s: a %s copy of %s was written' % (kind, label, earlier_name)
                if expected == 1 and find(after, 'My TeX page')['content'] != macro['content']:
                    return 'Latex: a renamed unedited %s did not take the current text' % earlier_name
        problem = check_renamed(tmp, update, former)
        if problem:
            return problem
    return None


def main():
    args = sys.argv[1:]
    if '--mutations' in args or '--mutation' in args:
        names = [args[args.index('--mutation') + 1]] if '--mutation' in args else list(MUTATIONS)
        ok = True
        for name in names:
            problem = run(name)
            print(('CAUGHT ' if problem else 'SURVIVED ') + name + (': ' + problem if problem else ''))
            ok = ok and bool(problem)
        sys.exit(0 if ok else 1)
    problem = run()
    if problem:
        sys.exit('FAIL: ' + problem)
    print('PASS: unedited bundled macros of earlier versions open texshop.app or take the reworded TeX Live, Program and Encoding texts after an update (3 earlier addresses, '
          'LaTeX and ConTeXt); the %d renamed macros of 5.59 and 6.00 RC take their new names and keep their keys; '
          'edited and user-renamed macros, other macros, links, binary and broken files are kept' % sum(map(len, RENAMED.values())))


if __name__ == '__main__':
    main()
