#!/usr/bin/env python3
"""Check mockup presentation against original control behavior; never show a window."""
from pathlib import Path
import argparse, subprocess, tempfile
from source_tree import include_args
root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--layout', type=Path, help='Alternative layout source for isolated mutation checks')
parser.add_argument('--mutations',action='store_true')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='texshop-presentation-') as folder:
    executable = Path(folder) / 'probe'
    command=['xcrun', 'clang', '-fobjc-arc', '-Werror', '-Wno-deprecated-declarations', '-mmacosx-version-min=14.6', *include_args(root), '-I', str(root/'Tests'), '-framework', 'Cocoa', str(root/'Tests/SettingsPresentation.m'), str(args.layout or root/'Sources/Settings/TSPrefPaneLayout.m'), str(root/'Sources/Settings/TSSettingsCategory.m'), str(root/'Sources/Settings/TSSettingsCategoryList.m'), '-o', str(executable)]
    def run(source):
        subprocess.run([str(source) if x==str(args.layout or root/'Sources/Settings/TSPrefPaneLayout.m') else x for x in command],check=True)
        return subprocess.run([str(executable),str(root/'Tests/Fixtures/SettingsDesign.json')],capture_output=True,text=True,timeout=30)
    original=args.layout or root/'Sources/Settings/TSPrefPaneLayout.m'
    result=run(original);assert result.returncode==0,(result.stdout,result.stderr);print(result.stdout,flush=True)
    if args.mutations:
        changes=[('top-aligned-accessory','[accessory.centerYAnchor constraintEqualToAnchor:view.centerYAnchor]','[accessory.topAnchor constraintEqualToAnchor:view.topAnchor constant:6]'),('invisible-card','self.layer.backgroundColor=TSSettingsCardColor().CGColor;','self.layer.backgroundColor=NSColor.clearColor.CGColor;'),('missing-separators','[line stroke];','/* omitted separator */')]
        changes.append(('path-note-full-width','!self.expandedAccessory && width > available','width > available'))
        text=original.read_text()
        for name,old,new in changes:
            assert text.count(old)==1,(name,text.count(old));changed=Path(folder)/'TSPrefPaneLayout.m';changed.write_text(text.replace(old,new));result=run(changed)
            expected={'path-note-full-width':'Path explanations stay inside the fixed name column','top-aligned-accessory':'Short button explanation centers the accessory','invisible-card':'Rendered card pixels differ','missing-separators':'Rendered rows have a visible separator'}[name]
            assert result.returncode and 'FAIL: '+expected in result.stderr,(name,result.stderr);print('DETECTED',name,result.stderr.strip(),flush=True)
        result=run(original);assert result.returncode==0;print('NORMAL CONTROL',result.stdout,flush=True)
