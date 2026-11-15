#!/usr/bin/env python3
"""The bundled Sparkle.framework orders build numbers after the earlier build versions (no window, no network).

With --mutation NAME the harness compiles a deliberately wrong expectation and must fail; --mutations runs them all."""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
MUTATIONS = {
    # A stable user on 5.59 must see the beta as newer, not older.
    'old-is-newer': ('Expect(@"5.59", NSOrderedAscending, @"1512"', 'Expect(@"5.59", NSOrderedDescending, @"1512"'),
    # A later commit must be a later build.
    'later-is-older': ('Expect(@"1512", NSOrderedAscending, @"1513"', 'Expect(@"1512", NSOrderedDescending, @"1513"'),
}


def run(mutation=None):
    source = root / 'Tests/SparkleVersionOrder.m'
    with tempfile.TemporaryDirectory(prefix='texshop-sparkle-version-order-') as tmp:
        if mutation:
            old, new = MUTATIONS[mutation]
            text = source.read_text(encoding='utf-8')
            assert text.count(old) == 1, 'mutation target must be unique: ' + mutation
            source = Path(tmp) / 'SparkleVersionOrder.m'
            source.write_text(text.replace(old, new), encoding='utf-8')
        frameworks = root / 'Frameworks'
        exe = Path(tmp) / 'sparkle-version-order'
        subprocess.run(['xcrun', 'clang', '-w', '-fobjc-arc', '-framework', 'Foundation', '-F', str(frameworks), '-framework', 'Sparkle',
                        '-Wl,-rpath,' + str(frameworks), str(source), '-o', str(exe)], check=True)
        return subprocess.run([str(exe)], capture_output=True, text=True, timeout=60)


def main():
    args = sys.argv[1:]
    if '--mutations' in args or '--mutation' in args:
        names = [args[args.index('--mutation') + 1]] if '--mutation' in args else list(MUTATIONS)
        ok = True
        for name in names:
            result = run(name)
            caught = result.returncode != 0
            print(('CAUGHT ' if caught else 'SURVIVED ') + name + ': ' + (result.stderr.strip().splitlines() or [''])[0])
            ok = ok and caught
        return 0 if ok else 1
    result = run()
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    return result.returncode


if __name__ == '__main__':
    sys.exit(main())
