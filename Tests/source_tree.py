"""Locate files in the Sources tree, which is split into subdirectories."""
from pathlib import Path


def source_dirs(root):
    base = Path(root) / 'Sources'
    return [base, *sorted(p for p in base.rglob('*') if p.is_dir())]


def include_args(root):
    return [arg for d in source_dirs(root) for arg in ('-I', str(d))]


def source_file(root, name):
    matches = sorted((Path(root) / 'Sources').rglob(str(name)))
    if len(matches) != 1:
        raise FileNotFoundError('Sources/**/%s: %d matches' % (name, len(matches)))
    return matches[0]


def git_show(root, rev, path):
    """Show a source file at an older revision, where Sources/ may still be flat."""
    import subprocess
    try:
        return subprocess.check_output(['git', 'show', '%s:%s' % (rev, path)], cwd=root, text=True,
                                       stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        if not str(path).startswith('Sources/'):
            raise
        flat = 'Sources/' + Path(path).name
        return subprocess.check_output(['git', 'show', '%s:%s' % (rev, flat)], cwd=root, text=True)
