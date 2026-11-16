#!/usr/bin/env python3
"""The Set Build Number phase: CFBundleVersion of the built application is the commit count of HEAD.

The script runs on copies of Resources/Info.plist in temporary git repositories; outside a full git
checkout of the source (a source archive, no git, a shallow clone) the value of Resources/Info.plist
stays and the build goes on. The project must run the phase last, after Info.plist is processed,
on every build. No window is shown and nothing outside temporary folders is written.
With --mutation NAME the harness runs against mutated sources and must fail; --mutations runs them all."""
from pathlib import Path
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
MUTATIONS = {
    # A source archive inside another repository takes that repository's count.
    'nested': ('[ "$(cd "$top" && pwd -P)" = "$(cd "$source_root" && pwd -P)" ] || keep', 'true || keep'),
    # A shallow clone gives a small, wrong count.
    'shallow': ('[ "$(git -C "$source_root" rev-parse --is-shallow-repository 2>/dev/null)" = false ] || keep', 'true || keep'),
    # A missing repository stops the build.
    'fail-without-git': ('    exit 0\n}', '    exit 1\n}'),
    # Only first-parent commits are counted.
    'first-parent': ('count=$(git -C "$source_root" rev-list --count HEAD', 'count=$(git -C "$source_root" rev-list --first-parent --count HEAD'),
    # The phase is skipped when its inputs have not changed, so a new commit keeps the old number.
    'not-always': ('alwaysOutOfDate = 1;', 'alwaysOutOfDate = 0;'),
    # The phase can run before Info.plist is processed.
    'no-plist-input': ('				"$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)",\n', ''),
}

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def git(cwd, *args):
    return subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', '-c', 'init.defaultBranch=master',
                           '-c', 'commit.gpgsign=false', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def repository(path, commits):
    path.mkdir(parents=True)
    git(path, 'init', '-q')
    for i in range(commits):
        git(path, 'commit', '-q', '--allow-empty', '-m', f'c{i}')
    return path


def build(script, source_root, products, path=None):
    """Run the phase on a fresh copy of Resources/Info.plist (binary, as Xcode writes it) and return CFBundleVersion."""
    plist = products / 'TeXShop.app/Contents/Info.plist'
    if not plist.exists():
        plist.parent.mkdir(parents=True)
        plist.write_bytes(plistlib.dumps(plistlib.loads((root / 'Resources/Info.plist').read_bytes()), fmt=plistlib.FMT_BINARY))
    env = dict(os.environ, SRCROOT=str(source_root), TARGET_BUILD_DIR=str(products), INFOPLIST_PATH='TeXShop.app/Contents/Info.plist')
    env.pop('GIT_DIR', None)
    env.pop('GIT_WORK_TREE', None)
    if path is not None:
        env['PATH'] = path
    result = subprocess.run(['/bin/sh', str(script)], env=env, capture_output=True, text=True, timeout=60)
    return result, plistlib.loads(plist.read_bytes())


def check_script(script, tmp):
    fallback = plistlib.loads((root / 'Resources/Info.plist').read_bytes())['CFBundleVersion']

    repo = repository(tmp / 'repo', 3)
    result, info = build(script, repo, tmp / 'p1')
    check(result.returncode == 0 and info['CFBundleVersion'] == '3', f'3 commits give build 3: {result.stdout}{result.stderr}')
    git(repo, 'commit', '-q', '--allow-empty', '-m', 'c3')
    result, info = build(script, repo, tmp / 'p1')
    check(result.returncode == 0 and info['CFBundleVersion'] == '4', 'A rebuild after another commit gives build 4')
    result, info = build(script, repo, tmp / 'p1')
    check(result.returncode == 0 and info['CFBundleVersion'] == '4', 'Building again gives the same number')
    check(info['CFBundleShortVersionString'] == fallback_short, 'The display version is not changed')

    # A merge counts the commits of both parents.
    git(repo, 'checkout', '-q', '-b', 'side', 'HEAD~2')
    git(repo, 'commit', '-q', '--allow-empty', '-m', 'side')
    git(repo, 'checkout', '-q', 'master')
    git(repo, 'merge', '-q', '--no-ff', '-m', 'merge', 'side')
    result, info = build(script, repo, tmp / 'p1')
    check(info['CFBundleVersion'] == '6', 'A merge counts the commits of both sides (git rev-list --count HEAD)')

    worktree = tmp / 'worktree'
    git(repo, 'worktree', 'add', '-q', '--detach', str(worktree), 'HEAD~1')
    result, info = build(script, worktree, tmp / 'p2')
    check(result.returncode == 0 and info['CFBundleVersion'] == '4', 'A git worktree is counted at its own HEAD')

    archive = tmp / 'archive/TeXShop'
    archive.mkdir(parents=True)
    result, info = build(script, archive, tmp / 'p3')
    check(result.returncode == 0 and info['CFBundleVersion'] == fallback and 'warning:' in result.stdout,
          f'A source archive keeps {fallback} with a warning: {result.stdout}{result.stderr}')

    nested = repo / 'unpacked/TeXShop'
    nested.mkdir(parents=True)
    result, info = build(script, nested, tmp / 'p4')
    check(result.returncode == 0 and info['CFBundleVersion'] == fallback, 'A source archive inside another repository keeps its own value')

    result, info = build(script, repo, tmp / 'p5', path='/bin:/usr/sbin:/sbin')
    check(result.returncode == 0 and info['CFBundleVersion'] == fallback, 'Without git the value stays and the build goes on')

    shallow = tmp / 'shallow'
    subprocess.run(['git', 'clone', '-q', '--depth', '1', repo.as_uri(), str(shallow)], check=True, capture_output=True)
    result, info = build(script, shallow, tmp / 'p6')
    check(result.returncode == 0 and info['CFBundleVersion'] == fallback, 'A shallow clone keeps the value')

    result, info = build(script, root, tmp / 'p7')
    expected = subprocess.run(['git', '-C', str(root), 'rev-list', '--count', 'HEAD'], capture_output=True, text=True).stdout.strip()
    check(info['CFBundleVersion'] == expected, f'This checkout gives git rev-list --count HEAD ({expected})')


def check_project(project):
    phase = re.search(r'\t\t(\w+) /\* Set Build Number \*/ = \{\n(.*?)\n\t\t\};', project, re.S)
    check(phase is not None, 'The project has the Set Build Number phase')
    if not phase:
        return
    ident, body = phase.groups()
    check('alwaysOutOfDate = 1;' in body, 'The phase runs on every build, so a new commit always gets its number')
    check('"$(TARGET_BUILD_DIR)/$(INFOPLIST_PATH)",' in body, 'The built Info.plist is an input, so the phase runs after Info.plist is processed')
    check('outputPaths = (\n\t\t\t);' in body, 'The built Info.plist is not declared as an output (ProcessInfoPlistFile produces it)')
    check('shellScript = "/bin/sh \\"$SRCROOT/Scripts/set-build-number.sh\\"\\n";' in body, 'The phase runs Scripts/set-build-number.sh')
    target = re.search(r'/\* TeXShop \*/ = \{\n\t\t\tisa = PBXNativeTarget;.*?buildPhases = \((.*?)\);', project, re.S)
    phases = re.findall(r'(\w+) /\*', target.group(1)) if target else []
    check(phases and phases[-1] == ident, 'The phase is the last phase of the application (Xcode signs after all phases)')
    # agvtool reads CURRENT_PROJECT_VERSION; the fallback in Resources/Info.plist is the same value.
    versions = set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project))
    fallback = plistlib.loads((root / 'Resources/Info.plist').read_bytes())['CFBundleVersion']
    check(versions == {fallback}, f'CURRENT_PROJECT_VERSION {versions} matches CFBundleVersion {fallback} of Resources/Info.plist')


def run(mutation=None):
    global failures, fallback_short
    failures = []
    fallback_short = plistlib.loads((root / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
    script = root / 'Scripts/set-build-number.sh'
    project = (root / 'TeXShop.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    with tempfile.TemporaryDirectory(prefix='texshop-build-number-') as name:
        tmp = Path(name).resolve()
        if mutation:
            old, new = MUTATIONS[mutation]
            text = script.read_text(encoding='utf-8')
            if text.count(old) == 1:
                script = tmp / 'set-build-number.sh'
                script.write_text(text.replace(old, new), encoding='utf-8')
            else:
                # The project has other script phases (Update About copyright year), so the mutation applies within this phase only.
                start = project.index('/* Set Build Number */ = {')
                end = project.index('\n\t\t};', start)
                phase = project[start:end]
                assert phase.count(old) == 1, 'mutation target must be unique: ' + mutation
                project = project[:start] + phase.replace(old, new) + project[end:]
        check_script(script, tmp)
        check_project(project)
    return failures


def main():
    args = sys.argv[1:]
    if '--mutations' in args or '--mutation' in args:
        names = [args[args.index('--mutation') + 1]] if '--mutation' in args else list(MUTATIONS)
        ok = True
        for name in names:
            found = run(name)
            print(('CAUGHT ' if found else 'SURVIVED ') + name + ': ' + (found[0] if found else ''))
            ok = ok and bool(found)
        return 0 if ok else 1
    found = run()
    for message in found:
        print('FAIL: ' + message, file=sys.stderr)
    if found:
        return 1
    print('PASS build number')
    return 0


if __name__ == '__main__':
    sys.exit(main())
