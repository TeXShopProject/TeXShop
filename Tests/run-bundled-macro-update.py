#!/usr/bin/env python3
"""A new version of TeXShop updates unedited bundled macros that open the former web site.

The macro TeXShop home page of earlier versions opened Richard Koch's former web site. When
TeXShop is updated, a copy in ~/Library/TeXShop/Macros whose content is still exactly an earlier
bundled text opens https://texshop.app/. The same holds for the macros reworded in 6.00, taken
as earlier versions bundled them (Tests/Fixtures/FormerBundledMacros.plist): View TeX Live file
writes TeX Live with the space, and the ConTeXt macro teTeX/TeXLive home page becomes TeX Live home
page, which opens https://tug.org/texlive/; a copy the user renamed keeps its name and content. Program
no longer offers metafont and context, and Encoding offers DOSKorean. A macro that was edited, and every other macro, keep
their content, names, keys and order. Nothing is written when no macro changes, a symbolic link
stays a link, a binary file stays binary, and a file that cannot be read is left alone.
TSAppDelegate does this only when the bundled files of a new version are copied.

Runs in a temporary folder only. With --mutation NAME the harness runs mutated sources and must
fail; --mutations runs them all."""
import copy, os, plistlib, subprocess, sys, tempfile
from pathlib import Path
from source_tree import include_args, source_file

root = Path(__file__).resolve().parents[1]
FORMER = ['https://pages.uoregon.edu/koch/texshop/texshop.html',
          'http://pages.uoregon.edu/koch/texshop/texshop.html',
          'http://www.uoregon.edu/~koch/texshop/texshop.html']
MUTATIONS = {
    # Any macro mentioning a former address is changed, edited ones too.
    'substring': ('    NSDictionary *target = [content isKindOfClass:[NSString class]] ? earlier[content] : nil;',
                  '    NSDictionary *target = [content isKindOfClass:[NSString class]] && [content containsString:@"uoregon"] ? earlier.allValues.firstObject : nil;'),
    # The reworded macros are not recognized.
    'reworded-ignored': ('    return @[\n        @{@"name": @"Program",', '    return @[]; (void)@[\n        @{@"name": @"Program",'),
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
                                                ('LatexProgram', 'Latex', 'Program', 'Program'),
                                                ('LatexEncoding', 'Latex', 'Encoding', 'Encoding')):
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
          'LaTeX and ConTeXt); edited macros, other macros, links, binary and broken files are kept')


if __name__ == '__main__':
    main()
