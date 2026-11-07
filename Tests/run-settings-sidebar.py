#!/usr/bin/env python3
"""Verify the settings shell without ordering windows or writing user defaults."""
from pathlib import Path
import argparse,subprocess,tempfile
parser=argparse.ArgumentParser()
parser.add_argument("output",nargs="?")
parser.add_argument("--app",type=Path)
args=parser.parse_args()
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='texshop-sidebar-') as td:
 p=Path(td);resources=args.app/'Contents/Resources' if args.app else None
 nib=resources/'SettingsWindow.nib' if resources else p/'SettingsWindow.nib'
 if resources is None:subprocess.run(['xcrun','ibtool','--compile',str(nib),str(r/'Resources/SettingsWindow.xib')],check=True)
 source=(r/'Sources/TSPreferences.m').read_text();start=source.index('- (BOOL)prepareSettingsWindow\n');method=source[start:source.index('\n}',start)+2]
 method=method.replace('NSBundle.mainBundle','FixtureBundle.mainBundle').replace('[[TSSettingsWindowController alloc]','[[TestController alloc]').replace('SUD','fixtureDefaults')
 test=(r/'Tests/SettingsSidebar.m').read_text().replace('// PRODUCTION_PREPARE',method)
 for marker,signature in [('PRODUCTION_VALIDATE','- (BOOL)settingsMayChangeCategory'),('PRODUCTION_FINISH','- (BOOL)finishPreferenceEditing:(BOOL)showError')]:
  start=source.index(signature+'\n');test=test.replace('// '+marker,source[start:source.index('\n}',start)+2])
 (p/'test.m').write_text(test)
 subprocess.run(['xcrun','clang' ,'-fobjc-arc','-Wall','-Wextra','-Wno-unused-parameter','-mmacosx-version-min=14.6','-Wnullability-completeness','-Wnullable-to-nonnull-conversion','-Werror=unguarded-availability-new','-I',str(r/'Tests'),'-I',str(r/'Sources'),'-framework','Cocoa',str(p/'test.m'),*[str(f) for f in sorted((r/'Sources').glob('TSSettings*.m'))],str(r/'Sources/TSPreferenceProfile.m'),'-o',str(p/'test')],check=True)
 out=Path(args.output) if args.output else p/'images';out.mkdir(parents=True,exist_ok=True)
 paths=sorted((resources or r/'Resources/Interfaces').glob('*.lproj/Preferences.nib/keyedobjects.nib'))
 assert len(paths)==12
 subprocess.run([str(p/'test'),str(nib),str(out) if args.output else "",*map(str,paths)],check=True)
