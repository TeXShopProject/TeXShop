#!/usr/bin/env python3
"""Compile the OgreKit Find panel from its sources into the bundled framework.

OgreKit is bundled as a built framework (Frameworks/OgreKit.framework, 2.1.12). Its
Find panel is laid out by OgreAdvancedFindPanel.nib in each localization. The sources
of those nibs, taken from OgreKit's tag 2.1.12 and then edited, are kept in
3rdparty/OgreKit-2.1.12-FindPanel/<language>.lproj/OgreAdvancedFindPanel.xib. This
script compiles each of them into the framework's Resources, replacing the compiled
nib files there. The framework's binary is not changed; Xcode signs the framework
again when it copies it into the application.

Run it from the top of the repository after editing a source:
    python3 Scripts/compile-ogrekit-find-panel.py
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
sources = root / '3rdparty/OgreKit-2.1.12-FindPanel'
resources = root / 'Frameworks/OgreKit.framework/Versions/A/Resources'

xibs = sorted(sources.glob('*.lproj/OgreAdvancedFindPanel.xib'))
assert xibs, sources
with tempfile.TemporaryDirectory(prefix='texshop-ogrekit-nib-') as tmp:
    for xib in xibs:
        language = xib.parent.name
        target = resources / language / 'OgreAdvancedFindPanel.nib'
        assert target.is_dir(), target
        out = Path(tmp) / f'{language}.nib'
        subprocess.run(['xcrun', 'ibtool', '--compile', str(out), str(xib)], check=True, stdout=subprocess.DEVNULL)
        for old in target.glob('keyedobjects*.nib'):
            old.unlink()
        if out.is_dir():
            for compiled in out.glob('keyedobjects*.nib'):
                shutil.copy2(compiled, target / compiled.name)
        else:
            shutil.copy2(out, target / 'keyedobjects.nib')
        print(language, 'OgreAdvancedFindPanel', flush=True)
