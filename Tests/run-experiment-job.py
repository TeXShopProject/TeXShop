#!/usr/bin/env python3
"""Run isolated Experiment jobs; optionally verify EOF and cancellation regression tests."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from source_tree import include_args

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check-mutations', action='store_true',
                    help='also prove the tests reject three broken EOF/cancellation variants')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
mutations = {
    'job-no-eof-wait': (
        'if (self.finished || !self.terminated || !self.reachedEOF)',
        'if (self.finished || !self.terminated)',
        'completion waits for descendant output and EOF'),
    'job-no-group-kill': (
        'if (group) kill(-group, SIGTERM);\n    else if',
        'if (0) kill(-group, SIGTERM);\n    else if',
        'cancellation sends TERM to descendants before KILL'),
    'job-no-sigkill': (
        'if (group && kill(-group, 0) == 0) kill(-group, SIGKILL);',
        ';',
        'cancellation escalates to KILL for TERM-ignoring descendants'),
}
with tempfile.TemporaryDirectory(prefix='texshop-experiment-test-') as directory:
    temp = Path(directory)
    original = (root / 'Sources/Typesetting/TSExperimentJob.m').read_text()
    variants = [('original', original, None)]
    if args.check_mutations:
        for name, (before, after, failure) in mutations.items():
            if original.count(before) != 1:
                raise SystemExit(f'{name}: expected exactly one mutation location')
            variants.append((name, original.replace(before, after), failure))
    for name, source, expected_failure in variants:
        source_path = temp / f'{name}.m'
        source_path.write_text(source)
        executable = str(temp / name)
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-framework', 'Foundation',
                        *include_args(root), str(root / 'Tests/ExperimentJob.m'),
                        str(source_path), '-o', executable], check=True)
        result = subprocess.run([executable], capture_output=True, text=True, timeout=45)
        if expected_failure is None:
            print(result.stdout, end='')
            print(result.stderr, end='')
            result.check_returncode()
        elif result.returncode != 1 or f'FAIL: {expected_failure}' not in result.stderr:
            raise SystemExit(f'{name}: regression test did not reject the mutation as expected\n'
                             f'{result.stdout}{result.stderr}')
        else:
            print(f'PASS: {name} rejected: {expected_failure}')
